variable "cluster_single_user" {}

resource "databricks_instance_pool" "smallest_nodes" {
  provider           = databricks.workspace
  instance_pool_name = "Smallest Nodes"
  min_idle_instances = 0
  max_capacity       = 2
  node_type_id       = "m5d.large"
  aws_attributes {
    availability           = "SPOT"
    spot_bid_price_percent = "100"
  }
  idle_instance_autotermination_minutes = 10
  preloaded_spark_versions              = ["14.3.x-photon-scala2.12"]
}

resource "databricks_cluster" "development_cluster" {
  provider                = databricks.workspace
  cluster_name            = "Development cluster"
  spark_version           = databricks_instance_pool.smallest_nodes.preloaded_spark_versions[0]
  instance_pool_id        = databricks_instance_pool.smallest_nodes.id
  autotermination_minutes = 30
  data_security_mode      = "SINGLE_USER"
  single_user_name        = var.cluster_single_user

  spark_conf = {
    # Single-node
    "spark.databricks.cluster.profile" : "singleNode"
    "spark.master" : "local[*]"
  }

  custom_tags = {
    "ResourceClass" = "SingleNode"
  }
}