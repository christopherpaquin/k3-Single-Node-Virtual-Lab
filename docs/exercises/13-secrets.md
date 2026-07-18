# Exercise 13: Secrets

**Module:** Configuration & Organization

**Prerequisite:** [Exercise 12 — ConfigMaps](12-configmaps.md)

---

## Theme

A Kubernetes **Secret** looks and behaves almost exactly like a ConfigMap
— same `--from-literal`/`--from-file` creation, same `envFrom`/volume
injection mechanics. The difference that actually matters isn't
mechanical, it's about what protection a Secret does and does not give
you, which is easy to overestimate if you only ever look at the surface.

This exercise deliberately decodes a Secret in one line, to make that
point concretely instead of just asserting it.

---

## What you'll do

- Create a Secret from literal values and from a file.
- Decode a Secret's value yourself, with a single command.
- Inject a Secret as environment variables and as mounted files.
- Compare `kubectl describe` against `kubectl get -o yaml` for a Secret.
- Compare Secrets and ConfigMaps directly.
- Understand exactly why base64 is not encryption.
- Review real risks around printing Secrets or committing them to source
  control.

---

## Step 1: Create a Secret from literal values

```bash
kubectl create secret generic db-credentials -n lab-apps \
  --from-literal=username=labadmin \
  --from-literal=password='S3cretPass!'
```

```bash
kubectl get secret db-credentials -n lab-apps -o yaml
```

Under `data:`, both values are present — but not as plain text the way a
ConfigMap's were in Exercise 12. They're base64-encoded strings. Keep this
output in mind; you'll come back to it directly in Step 4.

---

## Step 2: Create a Secret from a file

```bash
echo -n "sk_test_51H8xyz_fake_api_token" > token.txt
kubectl create secret generic api-token -n lab-apps --from-file=token.txt
```

```bash
kubectl get secret api-token -n lab-apps -o yaml
```

Same shape as Step 1 — one base64-encoded value, keyed by filename.

Delete the local file immediately rather than leaving it sitting around:

```bash
rm -f token.txt
```

This is worth internalizing as its own habit, separate from anything
Kubernetes does or doesn't protect: a plaintext secret file sitting in a
working directory (or worse, a shell history entry, or a CI log) is a real
exposure on its own, regardless of how it's eventually stored in the
cluster.

---

## Step 3: Inject a Secret as environment variables

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: secret-env-test
  namespace: lab-apps
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "echo username=$DB_USER; echo password=$DB_PASS"]
      env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
EOF
```

```bash
kubectl logs secret-env-test -n lab-apps
```

Both values print in plain text inside the container — Kubernetes decodes
Secrets automatically before injecting them; the base64 layer is purely
about how they're stored and transmitted through the API, not a barrier
the application itself ever has to deal with.

Clean up:

```bash
kubectl delete pod secret-env-test -n lab-apps
```

---

## Step 4: Decode a Secret's value yourself

You don't need a running Pod to read a Secret's real value — anyone who
can run `kubectl get secret` against it can decode it directly, in one
command:

```bash
kubectl get secret db-credentials -n lab-apps -o jsonpath='{.data.password}' | base64 -d
echo
```

That should print `S3cretPass!` in plain text, instantly, with no key,
password, or special tooling involved — just the standard `base64` command
every Linux system already has. Hold onto this result; it's the concrete
evidence behind Step 7 below.

---

## Step 5: Mount a Secret as files

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: secret-file-test
  namespace: lab-apps
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "ls -l /etc/db-credentials; cat /etc/db-credentials/username"]
      volumeMounts:
        - name: creds
          mountPath: /etc/db-credentials
  volumes:
    - name: creds
      secret:
        secretName: db-credentials
EOF
```

```bash
kubectl logs secret-file-test -n lab-apps
```

Each key becomes its own file, already decoded — same mechanism as a
ConfigMap volume in Exercise 12, just sourced from a Secret instead.

Clean up:

```bash
kubectl delete pod secret-file-test -n lab-apps
```

---

## Step 6: `describe` hides values — `get -o yaml` does not

```bash
kubectl describe secret db-credentials -n lab-apps
```

Look at the `Data` section — it shows key names and byte counts
(`password: 12 bytes`), not values. This looks like a safety feature, and
as a display default it's a reasonable one. But compare it against what
you already did in Step 4:

```bash
kubectl get secret db-credentials -n lab-apps -o yaml
```

The full, fully-recoverable base64 data is right there. `describe`'s
hidden-by-default display is a convenience, not an access control — it
doesn't restrict who can read the real value, only what one particular
command chooses to print. Anyone with permission to `get` this Secret
object at all — through `kubectl`, a script, or the API directly — can
recover the real value exactly as you did in Step 4. (You'll look at
exactly who has that kind of permission, and how to restrict it properly,
in the RBAC exercise later in this lab.)

---

## Step 7: Why base64 is not encryption

Step 4 is the entire argument: decoding a Secret's value took one piped
command, no key, no credential, no cryptographic material of any kind.
Base64 is a **reversible text encoding** — a way to represent arbitrary
binary data as plain ASCII text so it fits safely in a YAML/JSON field,
nothing more. Encryption, by contrast, requires a key to reverse; without
it, the ciphertext is (ideally) computationally useless. Base64 has no
such property — anyone with the encoded string already has everything
needed to recover the original.

By default, K3s's SQLite datastore does not encrypt Secrets at rest,
either — meaning a copy of that datastore file (or a backup of it, which
you'll look at directly in a later exercise) contains Secrets in this same
trivially-reversible form. Real encryption-at-rest for Secrets is
something you have to explicitly configure — it isn't the default
anywhere in vanilla Kubernetes or K3s.

---

## Step 8: Risks of printing Secrets or committing them to source control

A few concrete habits worth having, directly motivated by everything
above:

- **Don't `cat`, `echo`, or log a decoded Secret value** in a terminal
  you're screen-sharing, a CI log, or anywhere else with a wider audience
  than you intend — Step 4 showed you exactly how easy that value is to
  produce and expose.

- **Don't commit rendered Secret YAML to git.** A `data:` block is not
  meaningfully different from committing a plaintext credentials file —
  it's one `base64 -d` away from it, and git history keeps every version
  forever, even after a later commit "removes" it.

- **Prefer generating Secrets without ever writing the plaintext to
  disk**, using the same `--dry-run=client -o yaml | kubectl apply -f -`
  pattern from Exercise 12 — the values only ever exist as command
  arguments and in the API, never as a file you might forget to delete or
  accidentally `git add`:

  ```bash
  kubectl create secret generic demo-secret -n lab-apps \
    --from-literal=example=value \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl delete secret demo-secret -n lab-apps
  ```

- **For anything beyond a personal lab**, look into a dedicated secrets
  manager or a git-safe encrypted format (e.g. Sealed Secrets, SOPS,
  cloud-provider secret managers) rather than relying on raw Kubernetes
  Secrets as the system of record.

---

## Compare Secrets and ConfigMaps

| | ConfigMap | Secret |
|---|---|---|
| Storage format | Plain text | Base64-encoded (not encrypted) |
| `kubectl describe` shows values? | Yes | No — byte counts only |
| `kubectl get -o yaml` shows values? | Yes | Yes — fully recoverable, one command |
| Intended for | Non-sensitive config | Credentials, tokens, keys |
| Encrypted at rest by default? | No | No, in K3s's default configuration |

---

## Recap

In this exercise, you:

- Created Secrets from literal values and from a file, and cleaned up the
  plaintext file immediately afterward.

- Injected a Secret as environment variables and as mounted files — the
  same two mechanisms as ConfigMaps in Exercise 12.

- Decoded a Secret's real value yourself with a single `base64 -d`
  command, with no key or credential required.

- Confirmed `kubectl describe` hides Secret values by default, but
  `kubectl get -o yaml` does not — and that this is a display default, not
  an access control.

- Understand precisely why base64 is not encryption, and that K3s doesn't
  encrypt Secrets at rest by default either.

- Reviewed concrete risks around printing or committing Secrets, and a
  pattern (`--dry-run=client -o yaml | kubectl apply -f -`) for creating
  them without ever writing plaintext to disk.

---

**Previous:** [Exercise 12 — ConfigMaps](12-configmaps.md)

**Next:** [Exercise 14 — Logging and Troubleshooting](14-logging-and-troubleshooting.md)
