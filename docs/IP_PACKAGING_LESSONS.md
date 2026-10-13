# IP 打包踩雷紀錄（Vivado 2022.2）

| 症狀 | 原因 | 解法 |
|---|---|---|
| module not found / 檔案找不到 | `component.xml` 的路徑指向 `../src` | 改為 IP 內的 `hdl/` 相對路徑 |
| 檔案被當成 Verilog Header | `.v` 項目帶有 `isIncludeFile` | 移除該屬性後 Re-Package |
| 重複模組 / 舊程式被用到 | edit project 的 `imports` 有舊副本、舊 repository 路徑 | 刪除舊 imports 與舊 IP repo 路徑，重新 Refresh |
| Customization Parameters / Addressing 是空的 | 打包時頂層參數沒被辨識 | 頂層選對、Merge changes 後重新辨識 |
| `C_S00_AXI_ADDR_WIDTH = 4` | 預設值未改 | 設為 6（暫存器到 0x2C） |
| Merge changes 無限循環（19-377） | 重複檔案／參數不一致 | 清乾淨資料夾重打包 |
| 改了 RTL 卻沒生效 | OOC synthesis / ipshared 快取 | Reset output products → Generate（Global） |
| 板上讀值全 0 / Overlay 不符 | `.bit` 與 `.hwh` 不成對，或 kernel 沒重啟 | 同一次 build 的檔案、重啟 kernel |
