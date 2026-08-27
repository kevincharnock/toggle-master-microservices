variable "queue_name" {
  description = "Nome da fila principal"
  type        = string
  default     = "toggle-master-events"
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "message_retention_seconds" {
  description = "Padrao 4 dias"
  type        = number
  default     = 345600
}

variable "max_receive_count" {
  description = "Tentativas antes de mandar para a DLQ"
  type        = number
  default     = 3
}

variable "tags" {
  type    = map(string)
  default = {}
}
