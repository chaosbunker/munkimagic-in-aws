SHELL = /bin/bash

help:
	@echo -e "\n> \033[4mHelp\033[0m\n"
	@echo -e "  make configure,\033[35m\xe2\x86\x92\033[0m,Configure MunkiMagic\n\
	  make deploy,\033[35m\xe2\x86\x92\033[0m,Deploy MunkiMagic\n\
	  ,,\n\
	  make destroy,\033[35m\xe2\x86\x92\033[0m,Destroy MunkiMagic\n\
	  make reset,\033[35m\xe2\x86\x92\033[0m,Reset configuration" | column -s "," -t
	@echo ""

-include munki.env
export

.PHONY: munki.env

munki.env:
	@[[ ! -f ./munki.env ]] || [[ $(MAKECMDGOALS) == "reset" ]] \
		&& echo -e "cfn_template=munki_stack.yaml\n\
cfn_parameters=munki_stack_parameters.json\n\
zipfile=codebuild_scripts.zip\n\
cfn_gen_template=/tmp/gen_munki_stack.yaml\n\
" > munki.env

requirements:
	@[[ -z $${aws_region} || -z $${aws_profile} || -z $${munki_s3_bucket} || -z $${bootstrap_stack} || -z $${munki_stack} || -z $${munki_repo} || -z $${codebuild_scripts_bucket} ]] \
		&& echo -e "\n\033[31m!\033[0m Not all environment variables set. Please run \`make configure\`.\n" \
		&& exit 1 \
		|| :
	@if ! type aws &> /dev/null;then \
		echo -e "\n\033[31m!\033[0m Please install aws-cli\n"; \
		exit 1; \
	fi
	@if [[ $(MAKECMDGOALS) == "destroy" ]];then \
		if ! python2.7 -c "import boto3" 2>/dev/null;then \
			echo -e "\n\033[31m!\033[0m Please install boto3\n"; \
			exit 1; \
		fi; \
	fi


configure:
	@echo -e "\n\033[35m\xe2\x86\x92\033[0m \033[1;4mEnvironment\033[0m\n"
	@if [[ -z $${aws_profile} ]];then \
		while ! grep -q "^\[$${aws_profile}\]$$" ~/.aws/credentials;do \
			[ $${profile_check} ] && echo -e "\033[31mx\033[0m Profile '$${aws_profile}' does not exist."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter the name of the AWS profile to use: " aws_profile; \
			tput cuu 1 && tput el; \
			profile_check=1; \
		done; \
		echo "aws_profile=$${aws_profile}" >> munki.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m AWS profile set to '$${aws_profile}'"; \
	if [[ -z $${aws_region} ]];then \
		available_regions=( $$(aws --profile $${aws_profile} --region eu-west-1 ec2 describe-regions --query "Regions[].{Name:RegionName}" --output text 2>/dev/null) ); \
		if [[ -z $${available_regions[@]} ]];then \
			echo -e "x Setting region\033[33m\033[0m [CONNECTION ERROR]"; \
			exit 1; \
		fi; \
		while ! printf '%s\n' $${available_regions[@]} | grep -q "^$${aws_region}$$";do \
			[[ $${region_check} ]] && echo -e "\033[31mx\033[0m Region '$${aws_region}' does not exist."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter an AWS region [eu-west-1]: " aws_region; \
			tput cuu 1 && tput el; \
			aws_region=$${aws_region:-eu-west-1}; \
			aws_region=$$(echo $${aws_region} | tr "[:upper:]" "[:lower:]"); \
			region_check=1; \
		done; \
		echo "aws_region=$${aws_region}" >> munki.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Region set to '$${aws_region}'"; \
	if [[ -z $${munki_stack} ]];then \
		while [[ "$$(aws --profile $${aws_profile} --region $${aws_region} cloudformation describe-stacks --stack-name $${munki_stack} --query 'Stacks[].StackName' --output text 2>/dev/null)" == "$${munki_stack}" ]] || [[ ! $${munki_stack} =~ ^[A-Za-z-]+$$ ]];do \
			[[ $${munki_stack_check} ]] && echo -e "\033[31mx\033[0m Name '$${munki_stack}' taken or invalid."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter stack name: " munki_stack; \
			tput cuu 1 && tput el; \
			munki_stack_check=1; \
		done; \
		echo "munki_stack=$${munki_stack}" >> munki.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Stack name set to '$${munki_stack}'"; \
	if [[ -z $${bootstrap_stack} ]];then \
		bootstrap_stack=$${munki_stack}-bootstrap; \
		while [[ "$$(aws --profile $${aws_profile} --region $${aws_region} cloudformation describe-stacks --stack-name $${bootstrap_stack} --query 'Stacks[].StackName' --output text 2>/dev/null)" == "$${bootstrap_stack}" ]];do \
			LC_ALL=C rnd=$$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 3 | head -n 1); \
			bootstrap_stack=$${munki_stack}-bootstrap-$${rnd}; \
		done; \
		echo "bootstrap_stack=$${bootstrap_stack}" >> munki.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Bootstrap stack name set to '$${bootstrap_stack}'"; \
	if [[ -z $${munki_repo} ]];then \
		while [[ "$$(aws --profile $${aws_profile} --region $${aws_region} codecommit get-repository --repository-name $${munki_repo} --query 'repositoryMetadata.repositoryName' --output text 2>/dev/null)" == "$$(echo $${munki_repo} | tr "[:upper:]" "[:lower:]")" || -z $${munki_repo} || ! $${munki_repo} =~ ^[A-Za-z-]+$$ ]];do \
			[[ $${munki_repo_check} ]] && echo -e "\033[31mx\033[0m Name '$${munki_repo}' taken or invalid."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter name for CodeCommit repository [$${munki_stack}]: " munki_repo; \
			tput cuu 1 && tput el; \
			munki_repo=$${munki_repo:-$${munki_stack}}; \
			munki_repo=$$(echo $${munki_repo} | tr "[:upper:]" "[:lower:]"); \
			munki_repo_check=1; \
		done; \
		echo "munki_repo=$${munki_repo}" >> munki.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m CodeCommit repository name set to '$${munki_repo}'"; \
	if [[ -z $${munki_s3_bucket} ]];then \
		while ! aws --profile $${aws_profile} s3 ls "s3://$${munki_s3_bucket}" 2>&1 | grep -q 'NoSuchBucket';do \
			[[ $${munki_bucket_check} ]] && echo -e "\033[31mx\033[0m Name '$${munki_s3_bucket}' taken or invalid."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter name for munki repository bucket [$${munki_stack}]: " munki_s3_bucket; \
			tput cuu 1 && tput el; \
			munki_s3_bucket=$${munki_s3_bucket:-$${munki_stack}}; \
			munki_s3_bucket=$$(echo $${munki_s3_bucket} | tr "[:upper:]" "[:lower:]"); \
			munki_bucket_check=1; \
		done; \
		echo "munki_s3_bucket=$${munki_s3_bucket}" >> munki.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Munki bucket name set to '$${munki_s3_bucket}'"; \
	if [[ -z $${codebuild_scripts_bucket} ]];then \
		codebuild_scripts_bucket=$${munki_stack}-scripts; \
		while ! aws --profile $${aws_profile} s3 ls "s3://$${codebuild_scripts_bucket}" 2>&1 | grep -q 'NoSuchBucket';do \
			LC_ALL=C rnd=$$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 3 | head -n 1); \
			codebuild_scripts_bucket=$${munki_stack}-scripts-$${rnd}; \
		done; \
		echo "codebuild_scripts_bucket=$${codebuild_scripts_bucket}" >> munki.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m CodeBuild scripts bucket name set to '$${codebuild_scripts_bucket}'"; \
	if [[ -z $${munki_logging_bucket} ]];then \
		munki_logging_bucket=$${munki_stack}-logging; \
		while ! aws --profile $${aws_profile} s3 ls "s3://$${munki_logging_bucket}" 2>&1 | grep -q 'NoSuchBucket';do \
			LC_ALL=C rnd=$$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 3 | head -n 1); \
			munki_logging_bucket=$${munki_stack}-logging-$${rnd}; \
		done; \
		echo "munki_logging_bucket=$${munki_logging_bucket}" >> munki.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Logging bucket name set to '$${munki_logging_bucket}'"; \
	echo ""

deploy: requirements
	@echo -e "\n> \033[1;4mDeploy\033[0m"; \
	echo -e "\n\033[35m\xe2\x86\x92\033[0m \033[3mDeploying bootstrap stack\033[0m"; \
	aws --region $${aws_region} cloudformation deploy \
		--profile $${aws_profile} \
		--stack-name $${bootstrap_stack} \
		--template-file bootstrap_stack.yaml \
		--parameter-overrides \
		MunkiGitRepoName=$${munki_repo} \
			MunkiLoggingBucketName=$${munki_logging_bucket} \
			MunkiStackName=$${munki_stack} \
			MunkiGitRepoName=$${munki_stack} \
			MunkiRepoBucketName=$${munki_s3_bucket} \
			CodeBuildScriptsBucketName=$${codebuild_scripts_bucket} \
		--capabilities CAPABILITY_IAM; \
	echo -e "\n\033[35m\xe2\x86\x92\033[0m  \033[3mDeploying Munki stack \033[0m\n"
	@zip -r $${zipfile} ./munki ./sync_and_makecatalogs.sh ./buildspec.yml
	@echo ""
	@aws --profile $${aws_profile} s3 cp $${zipfile} s3://$${codebuild_scripts_bucket}
	@rm -f $${zipfile}
	@aws --region $${aws_region} cloudformation package \
		--template-file $${cfn_template} \
		--s3-bucket $${codebuild_scripts_bucket} \
		--output-template-file $${cfn_gen_template}
	@aws --region $${aws_region} cloudformation deploy \
		--profile $${aws_profile} \
		--stack-name $${munki_stack} \
		--template-file $${cfn_gen_template} \
		--parameter-overrides \
			AWSRegion=$${aws_region} \
			MunkiStackName=$${munki_stack} \
			MunkiGitRepoName=$${munki_repo} \
			bucket_name=$${munki_s3_bucket} \
			MunkiRepoBucketName=$${munki_s3_bucket} \
			CodeBuildScriptsBucketName=$${codebuild_scripts_bucket} \
			MunkiLoggingBucketName=$${munki_logging_bucket} \
			CodeBuildScriptsArchive=$${zipfile} \
		--capabilities CAPABILITY_NAMED_IAM; \
	echo "";
	@if [[ -f munki_admins.yaml ]];then \
		echo -e "> \033[1;4mUsers\033[0m"; \
		echo -e "\n\033[35m\xe2\x86\x92\033[0m \033[3mCreating additional users\033[0m"; \
		aws --region $${aws_region} cloudformation deploy \
			--profile $${aws_profile} \
			--stack-name $${munki_stack}-MunkiAdmins \
			--template-file munki_admins.yaml \
			--parameter-overrides \
				MunkiStackName=$${munki_stack} \
			--capabilities CAPABILITY_NAMED_IAM; \
	else \
		[[ $$(aws --profile $${aws_profile} --region $${aws_region} cloudformation describe-stacks --stack-name $${munki_stack}-MunkiAdmins --query 'Stacks[].StackName' --output text 2>&1) == "$${munki_stack}-MunkiAdmins" ]] \
			&& echo -e "\033[3;35m\xe2\x86\x92\033[0m \033[3mDeleting stack '$${munki_stack}-MunkiAdmins'\033[0m\n" \
			&& aws --profile $${aws_profile} --region $${aws_region} cloudformation delete-stack --stack-name "$${munki_stack}-MunkiAdmins" 2>&1; \
	fi; \
	echo ""

destroy: requirements
	@echo ""; \
	echo -e "\n\033[35m\xe2\x86\x92\033[0m \033[1;4mDestroy\033[0m"; \
	echo -en "\n\n"; \
	echo -e "  \033[1;31;mW A R N I N G  \xe2\x86\x92\033[0m  This action will \033[4mdestroy all resources\033[0m\n"; \
	echo -e "  that were created during deployment and \033[4mcannot be undone\033[0m.\033[0m\n"; \
	echo -e "  All data stored in these resources will be lost!\n"; \
	echo "";\
	while ! [[ $${response} =~ [yYnN] ]];do \
		read -rs -n 1 -p "$${1:-  Are you sure you want to continue?} [y/n]: " response; \
		case $${response} in \
			[yY]) echo -e "\033[32m[Yes]\033[0m";\
			;; \
			[nN]) echo -e "\033[31m[No]\033[0m\n";\
			echo -e "  Exiting.."; \
			exit; \
			;; \
			*) echo -e "\033[34m[Invalid Input]\033[0m"; \
		esac; \
	done; \
	stacks=( $${bootstrap_stack} $${munki_stack} ); \
	[[ -f munki_admins.yaml ]] && stacks+=( $${munki_stack}-MunkiAdmins ); \
	buckets=( $${munki_s3_bucket} $${munki_s3_bucket}-logging $${codebuild_scripts_bucket} $${munki_s3_bucket}-artifacts ); \
	echo -e "\n\n\033[3;35m\xe2\x86\x92\033[0m \033[3mEmptying buckets\033[0m\n"; \
	for bucket in $${buckets[@]};do \
		echo -en "  $${bucket}"; \
		if [[ $${bucket} == $${munki_s3_bucket}-artifacts || $${bucket} == $${codebuild_scripts_bucket} ]];then \
			export aws_profile bucket; \
			empty_bucket=$$(python2.7 -c 'import boto3; \
	import os; \
	bucket = os.getenv("bucket"); \
	profile = os.getenv("aws_profile"); \
	session = boto3.Session(profile_name=profile); \
	s3 = session.resource(service_name="s3"); \
	bucket = s3.Bucket(bucket); \
	bucket.object_versions.delete()' 2>&1); \
		else \
			empty_bucket=$$(aws --profile $${aws_profile} s3 rm s3://$${bucket} --recursive 2>&1); \
		fi; \
		if echo $${empty_bucket} | grep -q 'NoSuchBucket';then \
			echo -e " \033[33m[NOT FOUND]\033[0m"; \
			tput cuu 1 && echo -e "\033[33m?\033[0m"; \
		elif echo $${empty_bucket} | grep -q 'Access Denied';then \
			echo -e " \033[31m[ACCESS DENIED]\033[0m"; \
			tput cuu 1 && echo -e "\033[31mx\033[0m\n"; \
			echo -e "  Exiting.."; \
			exit; \
		elif echo $${empty_bucket} | grep -q 'Could not connect';then \
			echo -e " \033[31m[CONNECTION ERROR]\033[0m"; \
			tput cuu 1 && echo -e "\033[31mx\033[0m\n"; \
			echo -e "  Exiting.."; \
			exit; \
		else \
			echo -e " \033[32m[SUCCESS]\033[0m"; \
			tput cuu 1 && echo -e "\033[32m\xE2\x9C\x94\033[0m"; \
		fi; \
	done; \
	echo -e "\n\n\033[3;35m\xe2\x86\x92\033[0m \033[3mDeleting stacks\033[0m\n"; \
	for stack in $${stacks[@]};do \
		echo -en "  $${stack}"; \
		stack_status=$$(aws --profile $${aws_profile} --region $${aws_region} cloudformation describe-stacks --stack-name $${stack} --query 'Stacks[].StackName' --output text 2>&1); \
		if echo $${stack_status} | grep -q 'does not exist';then \
			echo -e " \033[33m[NOT FOUND]\033[0m"; \
			tput cuu 1 && echo -e "\033[33m?\033[0m"; \
		elif echo $${stack_status} | grep -q 'Could not connect';then \
			echo -e " \033[31m[CONNECTION ERROR]\033[0m"; \
			tput cuu 1 && echo -e "\033[31mx\033[0m\n"; \
			exit; \
			echo -e "  Exiting.."; \
		else \
			aws --profile $${aws_profile} --region $${aws_region} cloudformation delete-stack --stack-name "$${stack}" 2>&1; \
			echo -e " \033[34m[DELETE INITIATED]\033[0m"; \
			tput cuu 1 && echo -e "\033[34m\xE2\x9C\x94\033[0m"; \
		fi; \
	done; \
	echo ""

reset: munki.env
	@echo -e "\n\033[35m\xe2\x86\x92\033[0m \033[1;4mReset\033[0m"
	@[[ -f munki.env ]] \
		&& echo -e "\n\033[32m\xE2\x9C\x94\033[0m MunkiMagic configuration reset."
