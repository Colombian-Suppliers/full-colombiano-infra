apiVersion: v1
kind: Config
clusters:
- cluster:
    server: ${server_endpoint}
  name: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    user: ${cluster_name}-admin
  name: ${context_name}
current-context: ${context_name}
users:
- name: ${cluster_name}-admin
  user: {}

