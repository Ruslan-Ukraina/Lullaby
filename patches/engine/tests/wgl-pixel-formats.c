/* Which pixel formats an OpenGL backend lists and which WGL_ARB_pixel_format requests find one: the formats DescribePixelFormat
 * gives, then wglChoosePixelFormatARB for single attributes and for a few sets as games ask for them. Writes pfinfo.log in the
 * current directory. A request a game makes (COLOR_BITS >= 32, DOUBLE_BUFFER, DEPTH 24, STENCIL 8) must find a format: a driver
 * that lists RGBA8 with cColorBits 24 finds none for 32. */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
typedef BOOL (WINAPI *choose_t)(HDC, const int *, const FLOAT *, UINT, int *, UINT *);
typedef BOOL (WINAPI *getattr_t)(HDC, int, int, UINT, const int *, int *);
static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l) { return DefWindowProcA(h, m, w, l); }
int main(void)
{
    FILE *log = fopen("pfinfo.log", "w");
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = proc; wc.hInstance = GetModuleHandleA(NULL); wc.lpszClassName = "pfinfo"; wc.style = CS_OWNDC;
    RegisterClassA(&wc);
    HWND hwnd = CreateWindowA("pfinfo", "pfinfo", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 320, 240, NULL, NULL, wc.hInstance, NULL);
    HDC dc = GetDC(hwnd);
    int n = DescribePixelFormat(dc, 1, sizeof(PIXELFORMATDESCRIPTOR), NULL);
    fprintf(log, "formats: %d\n", n);
    for (int i = 1; i <= n && i <= 80; i++) {
        PIXELFORMATDESCRIPTOR p = {0};
        DescribePixelFormat(dc, i, sizeof p, &p);
        fprintf(log, "%2d flags 0x%05lx type %d color %d (r%d g%d b%d a%d) depth %d stencil %d accum %d\n", i, p.dwFlags, p.iPixelType,
                p.cColorBits, p.cRedBits, p.cGreenBits, p.cBlueBits, p.cAlphaBits, p.cDepthBits, p.cStencilBits, p.cAccumBits);
    }
    PIXELFORMATDESCRIPTOR pfd = {0};
    pfd.nSize = sizeof pfd; pfd.nVersion = 1; pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA; pfd.cColorBits = 32; pfd.cDepthBits = 24; pfd.cStencilBits = 8;
    int f = ChoosePixelFormat(dc, &pfd);
    fprintf(log, "ChoosePixelFormat(32/24/8): %d\n", f);
    HGLRC rc = wglCreateContext(dc); (void)rc;
    SetPixelFormat(dc, f, &pfd);
    rc = wglCreateContext(dc); wglMakeCurrent(dc, rc);
    choose_t choose = (choose_t)wglGetProcAddress("wglChoosePixelFormatARB");
    fprintf(log, "wglChoosePixelFormatARB %p\n", (void *)choose);
    static const struct { const char *n; int a[24]; } one[] = {
        {"none", {0}}, {"DRAW_TO_WINDOW", {0x2001,1,0}}, {"SUPPORT_OPENGL", {0x2010,1,0}}, {"DOUBLE_BUFFER", {0x2011,1,0}},
        {"PIXEL_TYPE=RGBA", {0x2013,0x202B,0}}, {"COLOR_BITS>=32", {0x2014,32,0}}, {"COLOR_BITS>=24", {0x2014,24,0}},
        {"ALPHA_BITS>=8", {0x201B,8,0}}, {"DEPTH>=24", {0x2022,24,0}}, {"STENCIL>=8", {0x2023,8,0}},
        {"SAMPLE_BUFFERS>=0", {0x2041,0,0}}, {"STEREO=0", {0x2012,0,0}}, {"SWAP_METHOD", {0x2007,0x2028,0}},
        {"SRGB_CAPABLE=1", {0x20A9,1,0}},
        {"game-like(32)", {0x2001,1,0x2010,1,0x2011,1,0x2013,0x202B,0x2014,32,0x2022,24,0x2023,8,0}},
        {"game-like(24)", {0x2001,1,0x2010,1,0x2011,1,0x2013,0x202B,0x2014,24,0x2022,24,0x2023,8,0}},
        {"RGBA8888 bits", {0x2001,1,0x2010,1,0x2011,1,0x2013,0x202B,0x2015,8,0x2017,8,0x2019,8,0x201B,8,0x2022,24,0x2023,8,0}} };
    for (unsigned k = 0; choose && k < sizeof one / sizeof *one; k++) {
        int fm[8] = {0}; UINT cnt = 99;
        BOOL ok = choose(dc, one[k].a, NULL, 8, fm, &cnt);
        fprintf(log, "%-22s ok %d count %u first %d\n", one[k].n, ok, cnt, fm[0]);
    }
    fclose(log);
    return 0;
}
