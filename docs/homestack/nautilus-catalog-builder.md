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

S3 endpoint 與 access key 請向部署端取得，或在主機上參考
`${DOCKERDIR}/secrets/nautilus-catalog-builder.env`。不要把實際 secret 寫入
repo。

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
export CATALOG_S3_ENDPOINT="http://<minio-host>:9000"
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
  homestack 的 Docker network。
