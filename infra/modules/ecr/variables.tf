variable "prefix" {
  description = "Repository name prefix."
  type        = string
}

variable "repositories" {
  description = "Repository names to create."
  type        = list(string)
}
