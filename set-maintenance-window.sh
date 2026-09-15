# 设置维护时间窗为周一凌晨 01:00 至 02:00 (时区 UTC+8)
az mysql flexible-server update \
  --resource-group "rg-tssnkur-prod" \
  --name "tssnkur-mysql-prod" \
  --maintenance-window day-of-week=1 hour=1 minute=0
