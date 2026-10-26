/* A minimal OpenGL program for trying an OpenGL backend: a window, a WGL context, a clear and a
 * triangle for about four seconds, then gltest.log in the current directory with GL_VENDOR,
 * GL_RENDERER, GL_VERSION and the frames drawn. Exit code 0 only if frames were swapped. */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>

static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l)
{
    if (m == WM_DESTROY) PostQuitMessage(0);
    return DefWindowProcA(h, m, w, l);
}

int main(void)
{
    FILE *log = fopen("gltest.log", "w");
    if (!log) return 90;
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = proc; wc.hInstance = GetModuleHandleA(NULL); wc.lpszClassName = "gltest"; wc.style = CS_OWNDC;
    RegisterClassA(&wc);
    HWND hwnd = CreateWindowA("gltest", "gltest", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 640, 480, NULL, NULL, wc.hInstance, NULL);
    HDC dc = GetDC(hwnd);
    PIXELFORMATDESCRIPTOR pfd = {0};
    pfd.nSize = sizeof pfd; pfd.nVersion = 1; pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA; pfd.cColorBits = 32; pfd.cDepthBits = 24;
    int fmt = ChoosePixelFormat(dc, &pfd);
    fprintf(log, "ChoosePixelFormat %d, SetPixelFormat %d\n", fmt, SetPixelFormat(dc, fmt, &pfd));
    HGLRC rc = wglCreateContext(dc);
    fprintf(log, "wglCreateContext %s\n", rc ? "ok" : "FAILED");
    if (!rc || !wglMakeCurrent(dc, rc)) { fprintf(log, "wglMakeCurrent FAILED\n"); fclose(log); return 91; }
    fprintf(log, "GL_VENDOR: %s\nGL_RENDERER: %s\nGL_VERSION: %s\n",
            (const char *)glGetString(GL_VENDOR), (const char *)glGetString(GL_RENDERER), (const char *)glGetString(GL_VERSION));
    DWORD start = GetTickCount(); int frames = 0;
    while (GetTickCount() - start < 4000) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        float t = (float)(GetTickCount() - start) / 4000.0f;
        glViewport(0, 0, 640, 480);
        glClearColor(0.15f + 0.3f * t, 0.12f, 0.45f - 0.3f * t, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glBegin(GL_TRIANGLES);
        glColor3f(1, 0, 0); glVertex2f(0.0f, 0.7f);
        glColor3f(0, 1, 0); glVertex2f(0.7f, -0.7f);
        glColor3f(0, 0, 1); glVertex2f(-0.7f, -0.7f);
        glEnd();
        if (SwapBuffers(dc)) frames++;
    }
    fprintf(log, "frames swapped: %d in %lu ms\n", frames, (unsigned long)(GetTickCount() - start));
    wglMakeCurrent(NULL, NULL); wglDeleteContext(rc);
    fclose(log);
    return frames > 0 ? 0 : 92;
}
