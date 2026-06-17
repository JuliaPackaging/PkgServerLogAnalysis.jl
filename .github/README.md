# GitHub Actions

## AWS OIDC

The sync workflow authenticates to AWS via OIDC rather than long-lived access key secrets.

### OIDC identity provider

Provider URL: `https://token.actions.githubusercontent.com`
Audience: `sts.amazonaws.com`
Account: `873569884612`

### IAM role: `PkgServerLogAnalysisSync`

ARN: `arn:aws:iam::873569884612:role/PkgServerLogAnalysisSync`

**Trust policy** — allows OIDC federation from the `master` branch only:

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
        "token.actions.githubusercontent.com:sub": "repo:JuliaPackaging/PkgServerLogAnalysis.jl:ref:refs/heads/master"
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

Set these in: Settings → Secrets and variables → Actions → Secrets

- `SSH_PRIVATE_KEY` — private key for rsync access to the pkg servers
- `HLL_KEY` — HyperLogLog key, base64-encoded: `base64 -w0 < hll_key`
