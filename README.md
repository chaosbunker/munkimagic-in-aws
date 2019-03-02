# MunkiMagic - Munki infrastructure in AWS

**Collaboratively manage software installs on OS X client machines.**

[Check out the Wiki](https://github.com/chaosbunker/munkimagic-in-aws/wiki/) to read about how MunkiMagic works and check out the [Demo page](https://github.com/chaosbunker/munkimagic-in-aws/wiki/Demo) of the Wiki to see it in action.

_**Warning:** Please note that by using this software you are creating real resources that might incur costs in your AWS account; refer to the pricing model for each service that is used; please review the code before running it; this software comes without warranty or guarantee; use at your own risk._

## Prerequisites
- A Mac running 10.12 or later
- An AWS Account and Administrator Access to it
- [aws-cli](https://docs.aws.amazon.com/cli/latest/userguide/cli-install-macos.html)
- boto3
- [munkitools](https://github.com/munki/munki/releases)
- [MunkiAdmin](https://github.com/hjuutilainen/munkiadmin/releases) (optional)

_Munki Admin's wanting to make changes to the munki repository can do so with the help of [munkimagic-MunkiAdmin](https://github.com/chaosbunker/munkimagic-MunkiAdmin). How-to instructions can be found [here](https://github.com/chaosbunker/munkimagic-in-aws/wiki/How-to-for-Munki-admins)._

---

## How to get started
### Overview of targets
```
~$: make help

> Help

  make configure  →  Configure MunkiMagic
  make deploy     →  Deploy MunkiMagic

  make destroy    →  Destroy MunkiMagic
  make reset      →  Reset configuration
```

### 1. Environment
Before deploying our munki stack, we need to configure MunkiMagic and set a few environment variables.

~$: `make configure`

### 2. Deploy

After all variables are set and written to munki.env we can deploy our Munki infrastructure. 

~$: `make deploy`

The deployment happens in two primary steps. 

**1. The 'bootstrap' stack is created with the following AWS resources:**

- a CodeCommit repository that will hold the manifests and pkgsinfo
- a CloudTrail for logging
- an S3 bucket that will act as the munki repository
- an S3 bucket that holds `codebuild_scripts.zip`, an archive that is zipped and uploaded to this bucket during deployement. It holds the `buildspec.yml` for the CodeBuild container, munkitools' `makecatalogs` script (which is needed to make the catalogs in the munki bucket) and `sync_and_makecatalogs.sh` (which is executed in the container on each run).
- an S3 bucket for munki repository bucket access logs and CloudTrail logging

**2. The 'Munki' stack is created with the following AWS resources:**
- a CodePipeline
- a CodeBuild Container
- IAM Resources
	- CodePipelineRole
	- CodeBuildRole
	- MunkiAdminPolicy
	- MunkiAdminAccess
	- MunkiClient
	- MunkiAdmin

- an S3 bucket that holds an archive of the CodeCommit repository as well as `codebuild_scripts.zip`. The archives are stored in this bucket each time the CodePipeline kicks in and are later received and used by the CodeBuild container as primary (codebuild_scripts.zip) and secondary artifacts (archive of CodeCommit repo).

### 3. Add additional Users (optional)

A separate IAM user should be created for each Munki Admin. This can be done by adding the IAM resource(s) to `munki_admins.yaml`.

```
  User1:
    Type: AWS::IAM::User
    Properties:
      UserName: !Join ['-', [ !Ref 'MunkiStackName', 'someonesname' ]]
      ManagedPolicyArns:
          - !Sub "arn:aws:iam::${AWS::AccountId}:policy/${MunkiStackName}-MunkiAdminAccess"
#  User2:
#    Type: AWS::IAM::User
#    Properties:
#      UserName: !Join ['-', [ !Ref 'MunkiStackName', 'someoneelsesname' ]]
#      ManagedPolicyArns:
#          - !Sub "arn:aws:iam::${AWS::AccountId}:policy/${MunkiStackName}-MunkiAdminAccess"
```
After adding or deleting a user to or from `munki_admins.yaml` we need to deploy the changes.

```
~$: make deploy
```


### 3. AWS Console

#### Security credentials
##### Access keys
After the Munki stack is created log into your AWS Console and generate one Access Key and Secret Key pair for the IAM User MunkiClient and a key pair for every Munki admin user that will be managing your Munki repository.

_MunkiAdminPolicy only gives write access to the /pkgs directory of the Munki repository bucket._

The MunkiClient Key pair is needed on the client to connect securely and directly to our Munki repo hosted in S3 via [s3-auth](https://github.com/waderobson/s3-auth) Middleware for Munki.

##### SSH keys for AWS CodeCommit
The SSH public key of the Munki admin needs to be uploaded and the resulting 'SSH key ID' then has to be given to the Munki admin.

__All credentials should be rotated regularly. New MunkiClient credentials can be deployed to clients by installing a configuration with the updated Keys via Munki.__

### 4. Create local munki repository

E.g. via MunkiAdmin, then run `munkiimport --configure` in your terminal.

If you saved your munki repo in _/path/to/munkimagic-MunkiAdmin/munkirepo_ set the repo url to _file:///path/to/munkimagic-MunkiAdmin/munkirepo_

### 5. Add manifests & packages and push changes to CodeCommit

See [How-to for Munki admins](https://github.com/chaosbunker/munkimagic-in-aws/wiki/How-to-for-Munki-admins) in the wiki.

### 6. Configure munki on the client

The easiest way to configure munki on the client is via a configuration profile. This profile can be created with [@erikberglund's](https://github.com/erikberglund) awesome [ProfileCreator](https://github.com/erikberglund/ProfileCreator).

We also need to allow our munki client to connect securely, and directly to our munki repo hosted in S3. To do that we use [s3-auth](https://github.com/waderobson/s3-auth) Middleware.

We can use [munki-pkg](https://github.com/munki/munki-pkg) to create a package that installs both the profile and s3-auth for us on the client.

---
### Destroy

To destroy all stacks and their resources:

~$: `make destroy`

This will empty all buckets and initiate the deletion of both stacks (_boto3 is needed to delete all versions in the versioning enabled buckets_).

### Reset
To reset the configuration:

~$: `make reset`

---

A few more details and the story behind this can be found [in this blog post](https://chaosbunker.com/projects/dev/munki-infrastructure-in-aws/).
