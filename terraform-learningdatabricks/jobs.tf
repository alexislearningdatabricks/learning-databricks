resource "databricks_job" "print_job" {
  provider = databricks.workspace
  name     = "Print job"

  run_as {
    user_name = databricks_cluster.development_cluster.single_user_name
  }

  task {
    task_key = "print_task"
    notebook_task {
      notebook_path = databricks_notebook.print.path
    }
    existing_cluster_id = databricks_cluster.development_cluster.id
  }
}