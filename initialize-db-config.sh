#!/bin/bash
# ==============================================================================
# AZURE CLI AUTOMATION & SERVER PARAMETERS CONFIGURATION SCRIPT
# PROJECT: EduFlow LMS DB Migration (Tssnkur Technology Co Ltd)
# ==============================================================================

set -e # 遇到任何子命令错误立即中断执行

# 定义全局变量
RESOURCE_GROUP="rg-tssnkur-prod"
SERVER_NAME="tssnkur-mysql-prod"
SUBSCRIPTION_ID="3bbc5821-b30f-476a-81c2-795ae462405a"
LOG_WORKSPACE_NAME="law-tssnkur-prod"

echo "=== 1. 切换至 Tssnkur 生产订阅 ==="
az account set --subscription "$SUBSCRIPTION_ID"

echo "=== 2. 开始微调参数组优化内存与并发性能 ==="

# 设定缓冲池内存大小为 24 GB
az mysql flexible-server parameter set \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$SERVER_NAME" \
  --name "innodb_buffer_pool_size" \
  --value "25769803776"

# 设定最大并发可用连接水位至 600
az mysql flexible-server parameter set \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$SERVER_NAME" \
  --name "max_connections" \
  --value "600"

# 启用并配置严格慢查询抓取
az mysql flexible-server parameter set \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$SERVER_NAME" \
  --name "slow_query_log" \
  --value "ON"

az mysql flexible-server parameter set \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$SERVER_NAME" \
  --name "long_query_time" \
  --value "1.0"

az mysql flexible-server parameter set \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$SERVER_NAME" \
  --name "log_queries_not_using_indexes" \
  --value "ON"

# 设定临时过渡认证协议
az mysql flexible-server parameter set \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$SERVER_NAME" \
  --name "default_authentication_plugin" \
  --value "mysql_native_password"

# 强制开启传输层 SSL 加密
az mysql flexible-server parameter set \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$SERVER_NAME" \
  --name "require_secure_transport" \
  --value "ON"

echo "=== 3. 关联 Log Analytics 工作区开启全面诊断审计日志流 ==="
SERVER_RESOURCE_ID=$(az mysql flexible-server show --resource-group "$RESOURCE_GROUP" --name "$SERVER_NAME" --query id -o tsv)
WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" --query id -o tsv)

az monitor diagnostic-settings create \
  --name "mysql-prod-diagnostics" \
  --resource "$SERVER_RESOURCE_ID" \
  --workspace "$WORKSPACE_RESOURCE_ID" \
  --logs '[
    {"category": "MySqlSlowLogs", "enabled": true, "retentionPolicy": {"days": 90, "enabled": true}},
    {"category": "MySqlAuditLogs", "enabled": true, "retentionPolicy": {"days": 90, "enabled": true}},
    {"category": "MySqlErrors", "enabled": true, "retentionPolicy": {"days": 90, "enabled": true}}
  ]' \
  --metrics '[{"category": "AllMetrics", "enabled": true, "retentionPolicy": {"days": 90, "enabled": true}}]'

echo "=== 4. 自动化参数优化与安全绑定已圆满达成！ ==="
