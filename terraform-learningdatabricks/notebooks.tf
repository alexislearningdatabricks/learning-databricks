resource "databricks_notebook" "print" {
  provider = databricks.workspace
  source = "${path.module}/print_test.py"
  path   = "/Workspace/Shared/print_test.py"
}