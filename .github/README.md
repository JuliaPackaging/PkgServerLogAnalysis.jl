# GitHub Actions

## AWS OIDC

The sync workflow authenticates to AWS via OIDC rather than long-lived access key secrets.

### OIDC identity provider

Provider URL: `https://token.actions.githubusercontent.com`
Audience: `sts.amazonaws.com`
Account: `873569884612`

### IAM role: `PkgServerLogAnalysisSync`

ARN: `arn:aws:iam::873569884612:role/PkgServerLogAnalysisSync`

**Trust policy** — allows OIDC federation from the `logsync` environment only
(which in turn only allows deployments from the `master` branch):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::873569884612:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:JuliaPackaging/PkgServerLogAnalysis.jl:environment:logsync"
      }
    }
  }]
}
```

**Inline policy: `S3Access`**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ],
    "Resource": [
      "arn:aws:s3:::julialang-pkgserver-logs",
      "arn:aws:s3:::julialang-pkgserver-logs/*",
      "arn:aws:s3:::julialang-pkgserver-logs-sanitized",
      "arn:aws:s3:::julialang-pkgserver-logs-sanitized/*"
    ]
  }]
}
```

## Secrets

Set these as secrets of the `logsync` environment (Settings → Environments →
`logsync`), not as repository secrets, so that they are only available to the
job on `master`:

- `HLL_KEY` — HyperLogLog key, base64-encoded: `base64 -w0 < hll_key`

## Package server access

The job joins the tailnet as `tag:logsync`, with a single-use preauth key
minted from its OIDC token by headscale-sts
(https://github.com/fredrikekre/headscale-sts). The headscale-sts rule
requires the `logsync` environment on `master` of this repository (matched by
repository and owner id). The tailnet policy allows `tag:logsync` to SSH
(Tailscale SSH) to `tag:packageserver` as the `logsync` user only, which has
no sudo or docker access and reads the logs from a read-only bind mount at
`/srv/logsync/nginx`.
