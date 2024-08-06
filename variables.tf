variable "cluster_name" {
  description = "name of of the ECS cluster"
  type        =  string
  default     = "simple-ngwaf-fg-template"
}

variable "task_count" {
  description = "number of tasks to start up"
  default     = 1
  type        = number
}

variable "agent_key" {
  description = "agent access key see: https://docs.fastly.com/en/ngwaf/accessing-agent-keys"
  default = "<your-key>"
  type = string 
}

variable "agent_secret" {
  description = "agent secret key see: https://docs.fastly.com/en/ngwaf/accessing-agent-keys"
  default = "<your-secret>"
  type = string 
}