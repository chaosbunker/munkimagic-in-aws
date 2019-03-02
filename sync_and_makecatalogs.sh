#!/bin/bash

set -ex

# Sync pkgsinfo
aws s3 sync "$CODEBUILD_SRC_DIR_MunkiGitRepoSourceArtifact/pkgsinfo" "s3://${MunkiRepoBucketName}/pkgsinfo" --delete --region $AWSRegion

# Sync manifests
aws s3 sync "$CODEBUILD_SRC_DIR_MunkiGitRepoSourceArtifact/manifests" "s3://${MunkiRepoBucketName}/manifests" --delete --region $AWSRegion

# Make catalogs
python munki/makecatalogs  -s --repo_url s3Repo --plugin s3Repo

# Remove local repository
rm -rf "$CODEBUILD_SRC_DIR_MunkiGitRepoSourceArtifact"


