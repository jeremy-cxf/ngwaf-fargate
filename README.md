## Simple Terraform Deployment of an ECS Fargate Service

This is a just a simple demo service deploying the Fastly NGWAF NGINX Module and the agent (sigsci-agent) to [ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html) Fargate using [Terraform](https://www.terraform.io/). 

This project deploys an [nginx](https://hub.docker.com/_/nginx) container behind an AWS [application load balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html) into the default AWS VPC.  
Also hooked up to [Cloudwatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/WhatIsCloudWatchLogs.html) for some simple monitoring (although it was somewhat necessary to do this anyway while writing). 

You'll need to set the variables appropriately in the vars file, see:
https://docs.fastly.com/en/ngwaf/accessing-agent-keys



```bash
variable "agent_key" {
  description = "agent access key see: https://docs.fastly.com/en/ngwaf/accessing-agent-keys"
  default = "<yourkey>"
  type = string 
}

variable "agent_secret" {
  description = "agent secret key see: https://docs.fastly.com/en/ngwaf/accessing-agent-keys"
  default = "<yoursecret>"
  type = string 
}
```

If you are not providing creds through some other means, you'll need to provide a path to your credentials via:

```bash
  shared_credentials_files = ["/path/to/credentials"]
  profile = "<yourawsprofile>"
```

e.g

```bash
provider "aws" {
  region = "us-east-1"
  shared_credentials_files = ["/home/jeremy/.aws/credentials"]
  profile = "jeremy-dev"
}
```


### Important Notes around Bind Mounts:
The module and the agent communicate over RPC via a Unix Socket, so a bind mount is needed.to share a volume to write to the socket and this is demonstrated.
However, theres a caveat, Fargate does not allow the agent socket bind to occur on `/var/run` which it has historically done, so the agent mounts on /sigsci/tmp (it detects this) instead.
The modules does not do this though, so the module configuration needs to be updated to look at /sigsci/tmp. You can review the nginx Dockerfile provided on how to hack around this quickly for this scenario, but ideally, you'll want a config mount to apply your nginx config if it deviates further, given the hack is based around the default nginx containers configuration. (however should still technically work with most).
```
Once all your config is set, you can:

```bash
terraform init
terraform plan
terraform apply
```

You'll then see your logs here:
https://us-east-1.console.aws.amazon.com/ecs/v2/clusters/simple-ngwaf-fg-template-cluster/services/simple-ngwaf-fg-template-service/logs?region=us-east-1

The output provides the reachable FQDN:
simple-ngwaf-fg-template-alb-xxxxxxx.us-east-1.elb.amazonaws.com:80

E.g:
```bash
curl "http://simple-ngwaf-fg-template-alb-1496400485.us-east-1.elb.amazonaws.com:80?script=<script>cmd.exe</script>"                     
<html>
<head><title>406 Not Acceptable</title></head>
<body>
<center><h1>406 Not Acceptable</h1></center>
<hr><center>nginx/1.25.4</center>
</body>
```

