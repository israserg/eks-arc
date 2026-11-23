#!/usr/bin/env bash
# Prepares the current shell for Terraform and kubectl on this project.
#
# Use "source", not "bash", so the settings stay in your shell:
#   source scripts/run.sh
#
# It does NOT set the GitHub token. Set that yourself in the same shell:
#   export TF_VAR_github_token='<your token>'

# Remove old exported credentials. They override the profile and expire after 15 minutes.
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# "tf" profile (see ~/.aws/config) fetches fresh credentials from your "aws login" session
# whenever Terraform needs them, so long applies do not expire halfway through.
export AWS_PROFILE=tf
export AWS_REGION=eu-north-1

# This file must be sourced, otherwise the exports above vanish when it exits.
if ! (return 0 2>/dev/null); then
  echo "Run this as:  source scripts/run.sh   (not: bash scripts/run.sh)" >&2
  exit 1
fi

echo "AWS_PROFILE=$AWS_PROFILE  AWS_REGION=$AWS_REGION"

# Check the sign-in. If it fails, run: aws login --profile default
if arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
  echo "AWS identity: $arn"
else
  echo "AWS sign-in not valid. Run: aws login --profile default" >&2
fi

# Report whether the token is set, without printing it.
if [ -n "${TF_VAR_github_token:-}" ]; then
  echo "TF_VAR_github_token: set"
else
  echo "TF_VAR_github_token: NOT set (needed for plan/apply: export TF_VAR_github_token='<your token>')"
fi

unset arn
