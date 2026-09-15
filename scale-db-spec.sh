# 升级命令：将计算规格 Standard_D8ds_v4 升级至 Standard_D16ds_v4 (16 核, 64 GB 内存)
az mysql flexible-server update \
  --resource-group "rg-tssnkur-prod" \
  --name "tssnkur-mysql-prod" \
  --sku-name "Standard_D16ds_v4"

# 调优扩容：如果存储预估超载，将存储从 512GB 在线升级至 1TB (注意：只能上调，不能下调)
az mysql flexible-server update \
  --resource-group "rg-tssnkur-prod" \
  --name "tssnkur-mysql-prod" \
  --storage-size 1024
