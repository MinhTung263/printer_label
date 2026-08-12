// Interface AIDL của Sunmi InnerPrinterService (woyou.aidl.service).
// Chỉ khai báo các hàm plugin thực sự dùng — AIDL cho phép khai báo tập con,
// MIỄN LÀ thứ tự khai báo giống hệt bản gốc của Sunmi, vì transaction ID được
// sinh theo THỨ TỰ chứ không theo tên. Đảo thứ tự = gọi nhầm hàm.
package woyou.aidlservice.jiuiv5;

import woyou.aidlservice.jiuiv5.ICallback;

interface IWoyouService {
    // 1
    void printerInit(in ICallback callback);
    // 2
    void printerSelfChecking(in ICallback callback);
    // 3
    String getPrinterSerialNo();
    // 4
    String getPrinterVersion();
    // 5
    String getPrinterModal();
    // 6
    int getPrintedLength();
    // 7
    void updatePrinterState();
    // 8
    void sendRAWData(in byte[] data, in ICallback callback);
    // 9
    void setAlignment(int alignment, in ICallback callback);
    // 10
    void setFontName(String typeface, in ICallback callback);
    // 11
    void setFontSize(float fontsize, in ICallback callback);
    // 12
    void printerText(String text, in ICallback callback);
    // 13
    void printTextWithFont(String text, String typeface, float fontsize, in ICallback callback);
    // 14
    void printColumnsText(in String[] colsTextArr, in int[] colsWidthArr, in int[] colsAlign, in ICallback callback);
    // 15
    void printBitmap(in android.graphics.Bitmap bitmap, in ICallback callback);
    // 16
    void printBarCode(String data, int symbology, int height, int width, int textposition, in ICallback callback);
    // 17
    void printQRCode(String data, int modulesize, int errorlevel, in ICallback callback);
    // 18
    void printOriginalText(String text, in ICallback callback);
    // 19
    void commitPrinterBuffer();
    // 20
    void printColumnsString(in String[] colsTextArr, in int[] colsWidthArr, in int[] colsAlign, in ICallback callback);
    // 21
    void lineWrap(int n, in ICallback callback);
    // 22
    void enterPrinterBuffer(boolean clean);
    // 23
    void exitPrinterBuffer(boolean commit);
    // 24
    void cutPaper(in ICallback callback);
    // 25
    void getPrinterFactory();
    // 26
    int getCutPaperTimes();
    // 27
    void openDrawer(in ICallback callback);
    // 28
    int getOpenDrawerTimes();
    // 29
    void printBitmapCustom(in android.graphics.Bitmap bitmap, int type, in ICallback callback);
    // 30
    int getPrinterMode();
    // 31
    int getPrinterBBMDistance();
    // 32
    void setPrinterStyle(int key, int value);
    // 33
    int getServicePermit();
    // 34
    int getPrinterDensity();
    // 35
    void printerSelfChecking1(in ICallback callback);
    // 36
    String getPrinterName();
}
