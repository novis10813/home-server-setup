# Nautilus catalog builder

`nautilus-catalog-builder` 會把 recorder 上傳到 MinIO/S3 的 raw market data
轉成 Nautilus Trader 可讀的 Parquet catalog。給本地回測程式使用時，最簡單的
方式是直接從 S3 以唯讀方式載入 catalog，不需要連 NATS 或 QuestDB。

## Catalog 位置

| 項目 | 值 |
|------|----|
| S3 bucket | `nautilus-data` |
| Catalog prefix | bucket root |
| 已建置 symbols | `BNBUSDT.BINANCE`, `BTCUSDT.BINANCE`, `ETHUSDT.BINANCE` |
| 已建置 data types | `trade_tick`, `order_book_depths` |

Docker 內部 builder 使用 `http://minio:9000`。本地或 LAN 回測程式請使用
`https://s3.${DOMAINNAME_1}` 與 path-style request，並使用只允許讀取
`nautilus-data` 的專用 credential。部署主機上的 reader credential 由
`${DOCKERDIR}/secrets/minio.env` 管理；不要把實際 secret 寫入 repo，也不要把
builder 或 archiver 的寫入 credential 提供給回測程式。

## 最小本地專案

在本地機器建立一個乾淨目錄：

```bash
mkdir -p ~/nautilus-backtest-example
cd ~/nautilus-backtest-example
```

建立 `pyproject.toml`：

```toml
[project]
name = "nautilus-backtest-example"
version = "0.1.0"
requires-python = ">=3.13"
dependencies = [
    "nautilus-trader>=1.228.0",
    "s3fs",
]
```

設定連線環境變數：

```bash
export CATALOG_S3_ENDPOINT="https://s3.<domain>"
export CATALOG_S3_ACCESS_KEY="<access-key>"
export CATALOG_S3_SECRET_KEY="<secret-key>"
export CATALOG_OUTPUT_S3_BUCKET="nautilus-data"
```

建立 `read_catalog.py`：

```python
from __future__ import annotations

import os

from nautilus_trader.model.data import OrderBookDepth10
from nautilus_trader.model.identifiers import InstrumentId
from nautilus_trader.persistence.catalog.parquet import ParquetDataCatalog


def make_catalog() -> ParquetDataCatalog:
    endpoint = os.environ["CATALOG_S3_ENDPOINT"]
    access_key = os.environ["CATALOG_S3_ACCESS_KEY"]
    secret_key = os.environ["CATALOG_S3_SECRET_KEY"]
    bucket = os.environ.get("CATALOG_OUTPUT_S3_BUCKET", "nautilus-data")

    return ParquetDataCatalog(
        bucket,
        fs_protocol="s3",
        fs_storage_options={
            "key": access_key,
            "secret": secret_key,
            "client_kwargs": {"endpoint_url": endpoint},
            "config_kwargs": {"s3": {"addressing_style": "path"}},
        },
        fs_rust_storage_options={
            "endpoint_url": endpoint,
            "access_key_id": access_key,
            "secret_access_key": secret_key,
            "region": "us-east-1",
            "allow_http": "true",
            "virtual_hosted_style_request": "false",
        },
    )


def main() -> None:
    catalog = make_catalog()
    instrument = InstrumentId.from_str("BTCUSDT.BINANCE")
    start = "2026-06-17T00:00:00Z"
    end = "2026-06-17T00:01:00Z"

    trades = catalog.trade_ticks(
        instrument_ids=[instrument],
        start=start,
        end=end,
    )
    depths = catalog.query(
        OrderBookDepth10,
        identifiers=[str(instrument)],
        start=start,
        end=end,
    )

    print("data types:", catalog.list_data_types())
    print("trade ticks:", len(trades))
    print("depth10 rows:", len(depths))
    if trades:
        print("first trade:", trades[0])
    if depths:
        print("first depth:", depths[0])


if __name__ == "__main__":
    main()
```

執行：

```bash
uv run python read_catalog.py
```

## 接到 BacktestEngine

讀出來的 `trades` / `depths` 已經是 Nautilus Trader data objects，可以直接
餵給 `BacktestEngine.add_data(...)`。實際策略、instrument definition、venue
與 account 設定仍由回測專案自己負責。

最小資料載入形狀如下：

```python
engine.add_data(trades)
engine.add_data(depths)
```

## 注意事項

- 目前這個 catalog 使用 MinIO/S3 path-style request；`config_kwargs` 與
  `virtual_hosted_style_request=false` 都要保留。
- 目前驗證過的 Nautilus Trader 版本需要直接建構 `ParquetDataCatalog(...)`。
  不建議用 `ParquetDataCatalog.from_uri("s3://nautilus-data")`，這個路徑在本
  環境的 `s3fs` 組合會帶入不相容的 `host` option。
- `fs_rust_storage_options` 的 endpoint key 必須使用 `endpoint_url`，不要使用
  `aws_endpoint`。
- 本範例只讀取已轉好的 catalog，不會觸發轉檔、不會寫入 S3，也不需要連
  homestack 的 Docker network。若範例跑在 Homestack Docker network 內，
  endpoint 改用 `http://minio:9000`。

## One-shot 容器部署與排程

`nautilus-catalog-builder` 是停止後由 cron 每日呼叫 Docker `start` 的
one-shot 容器。Docker 會在容器建立時固定 `env_file` 與 Compose environment；
只修改 Compose 或 secrets 不會更新既有的停止容器。修改 image、endpoint、
credentials 或其他 builder 設定後，必須先 recreate：

```bash
cd /opt/docker
docker compose -f docker-compose-homestack.yml create --build --force-recreate nautilus-catalog-builder
```

recreate 後應確認容器內 endpoint 是內網 MinIO，且 credential 與目前 secret
一致。比較 credential 時只輸出相等與否，不要印出實際值。

每日排程正常時，catalog 最多落後一個尚未結束的 UTC 日。檢查最近三個完整日：

```bash
docker compose -f docker-compose-homestack.yml run --rm nautilus-catalog-builder \
  plan --start YYYY-MM-DD --end YYYY-MM-DD
```

`planned: []` 可以表示輸出已存在且 raw manifest hash 未變；應同時檢查 catalog
最新 timestamp。若 raw 已有完整 closed day、catalog 卻超過一天未前進，先檢查
容器設定漂移與 builder logs，再執行指定日期的 `build-day` 或 `backfill`。

Alpha/backtest client 應使用只允許讀取 `nautilus-data` 的專用 MinIO credential，
不要使用 builder 或 archiver 的寫入 credential。
