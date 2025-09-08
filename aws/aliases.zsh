# AWS CLI shortcuts

# Core AWS commands
alias awsl='aws configure list'
alias awswho='aws sts get-caller-identity'
alias awsregion='aws configure get region'

# S3 shortcuts
alias s3ls='aws s3 ls'
alias s3cp='aws s3 cp'
alias s3mv='aws s3 mv'
alias s3rm='aws s3 rm'
alias s3sync='aws s3 sync'
alias s3mb='aws s3 mb'
alias s3rb='aws s3 rb'
alias s3web='aws s3 website'

# EC2 shortcuts
alias ec2ls='aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,PublicIpAddress,Tags[?Key==`Name`]|[0].Value]" --output table'
alias ec2start='aws ec2 start-instances --instance-ids'
alias ec2stop='aws ec2 stop-instances --instance-ids'
alias ec2reboot='aws ec2 reboot-instances --instance-ids'
alias ec2terminate='aws ec2 terminate-instances --instance-ids'
alias ec2ip='aws ec2 describe-instances --query "Reservations[*].Instances[*].[Tags[?Key==`Name`]|[0].Value,PublicIpAddress]" --output table'

# Lambda shortcuts
alias lambdals='aws lambda list-functions --query "Functions[*].[FunctionName,Runtime,LastModified]" --output table'
alias lambdainvoke='aws lambda invoke'
alias lambdalogs='aws logs tail --follow'
alias lambdadeploy='aws lambda update-function-code'

# CloudFormation shortcuts
alias cfnls='aws cloudformation list-stacks --query "StackSummaries[?StackStatus!=`DELETE_COMPLETE`].[StackName,StackStatus,LastUpdatedTime]" --output table'
alias cfnvalidate='aws cloudformation validate-template'
alias cfnevents='aws cloudformation describe-stack-events'
alias cfnoutputs='aws cloudformation describe-stacks --query "Stacks[*].[StackName,Outputs]" --output table'

# ECS shortcuts
alias ecsls='aws ecs list-clusters'
alias ecsservices='aws ecs list-services'
alias ecstasks='aws ecs list-tasks'
alias ecsdescribe='aws ecs describe-services'

# RDS shortcuts
alias rdsls='aws rds describe-db-instances --query "DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,Engine,DBInstanceClass]" --output table'
alias rdsstart='aws rds start-db-instance --db-instance-identifier'
alias rdsstop='aws rds stop-db-instance --db-instance-identifier'

# IAM shortcuts
alias iamusers='aws iam list-users --query "Users[*].[UserName,CreateDate]" --output table'
alias iamroles='aws iam list-roles --query "Roles[*].[RoleName,CreateDate]" --output table'
alias iamgroups='aws iam list-groups --query "Groups[*].[GroupName,CreateDate]" --output table'
alias iampolicies='aws iam list-policies --scope Local --query "Policies[*].[PolicyName,CreateDate]" --output table'

# SSM shortcuts
alias ssmls='aws ssm describe-parameters --query "Parameters[*].[Name,Type,LastModifiedDate]" --output table'
alias ssmget='aws ssm get-parameter --with-decryption --query "Parameter.Value" --output text --name'
alias ssmput='aws ssm put-parameter'
alias ssmsession='aws ssm start-session --target'

# CloudWatch shortcuts
alias cwlogs='aws logs describe-log-groups --query "logGroups[*].[logGroupName,storedBytes,retentionInDays]" --output table'
alias cwtail='aws logs tail --follow'
alias cwalarms='aws cloudwatch describe-alarms --query "MetricAlarms[*].[AlarmName,StateValue,MetricName]" --output table'

# DynamoDB shortcuts
alias dynamols='aws dynamodb list-tables'
alias dynamoscan='aws dynamodb scan --table-name'
alias dynamoquery='aws dynamodb query --table-name'

# Cost Explorer shortcuts
alias awscost='aws ce get-cost-and-usage --time-period Start=$(date -u -d "30 days ago" +%Y-%m-%d),End=$(date -u +%Y-%m-%d) --granularity MONTHLY --metrics "UnblendedCost" --group-by Type=DIMENSION,Key=SERVICE'

# Profile shortcuts (work with use_aws_profile function)
alias awsprofile='current_aws_profile'
alias awsprofiles='list_aws_profiles'
alias awsclear='clear_aws_profile'

# Common AWS operations with JSON output
alias awsjson='aws --output json'
alias awstable='aws --output table'
alias awstext='aws --output text'