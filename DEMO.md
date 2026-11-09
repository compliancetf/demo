# Demo script

Copy and run from the repository root. Each step is one talking point.

## 0. Before the call

```sh
export AWS_PROFILE=demo CTF_REGISTRY_TOKEN=...   # registry token from compliance.tf
make check-tools login init
curl -s -o /dev/null -w '%{http_code}\n' "$(terraform -chdir=infra output -raw api_url)"   # expect 200
```

## 1. The app is live, built from upstream modules

The running stack is branch `baseline`: plain terraform-aws-modules with insecure inputs.

```sh
git diff master baseline -- infra | head -60
```

## 2. ctfkit flags the code before any plan

```sh
git checkout baseline && make scan; git checkout master
```

One error per module: the source is not a compliance.tf endpoint.

## 3. Change only the source line: the plan fails

```sh
make demo-pr
```

Open the PR. The `terraform plan` comment names each control and its fix
(KMS rotation, SNS encryption, public IPs, log retention and encryption, IMDSv2).
The same check offline:

```sh
make verify-fail
```

## 4. Apply the fixes: in-place changes only

```sh
make demo-fix
```

The PR plan turns green: 0 to add, 0 to destroy, only the insecure attributes flip.
The same check offline (on `master`):

```sh
make verify
```

## 5. A recorded exception

```sh
make exception-pr
```

30-day container logs: `?disable=cloudwatch_log_group_retention_period_365` on one module.
The plan passes, but `ctfkit scan` fails and names the disabled control.

```sh
make record-exception
```

An entry in `.github/ctfkit/exceptions.yaml` with owner, approver and review date turns the scan green.
`.github/` needs a code owner review, so nobody approves their own exception.

## 6. Evidence for the auditor

```sh
make report
```

The same table is in the README, updated by the `readme report` workflow on every merge.

## Reset after the call

```sh
gh pr close demo/log-retention-exception --delete-branch
gh pr close demo/iso27001 --delete-branch
```
