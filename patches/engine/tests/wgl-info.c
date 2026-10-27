/* What an OpenGL backend offers a game that asks for a 4.4 core context, as the SCS games do: version strings,
 * the extension list, a few limits, and the pointers for the functions a loader asks for. Writes glinfo.log in the
 * current directory. */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <string.h>

#define WGL_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB 0x2092
#define WGL_CONTEXT_PROFILE_MASK_ARB 0x9126
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB 1
#define GL_NUM_EXTENSIONS 0x821D
#define GL_EXTENSIONS_I 0x1F03
#define GL_MAX_TEXTURE_SIZE_ 0x0D33
typedef const GLubyte *(APIENTRY *getstringi_t)(GLenum, GLuint);
typedef HGLRC (APIENTRY *createattribs_t)(HDC, HGLRC, const int *);

static LRESULT CALLBACK proc(HWND h, UINT m, WPARAM w, LPARAM l) { return DefWindowProcA(h, m, w, l); }

int main(void)
{
    FILE *log = fopen("glinfo.log", "w");
    if (!log) return 90;
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = proc; wc.hInstance = GetModuleHandleA(NULL); wc.lpszClassName = "glinfo"; wc.style = CS_OWNDC;
    RegisterClassA(&wc);
    HWND hwnd = CreateWindowA("glinfo", "glinfo", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 320, 240, NULL, NULL, wc.hInstance, NULL);
    HDC dc = GetDC(hwnd);
    PIXELFORMATDESCRIPTOR pfd = {0};
    pfd.nSize = sizeof pfd; pfd.nVersion = 1; pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA; pfd.cColorBits = 32; pfd.cDepthBits = 24; pfd.cStencilBits = 8;
    int fmt = ChoosePixelFormat(dc, &pfd);
    SetPixelFormat(dc, fmt, &pfd);
    HGLRC old = wglCreateContext(dc);
    wglMakeCurrent(dc, old);
    createattribs_t create = (createattribs_t)wglGetProcAddress("wglCreateContextAttribsARB");
    fprintf(log, "wglCreateContextAttribsARB: %p\n", (void *)create);
    int attribs[] = { WGL_CONTEXT_MAJOR_VERSION_ARB, 4, WGL_CONTEXT_MINOR_VERSION_ARB, 4,
                      WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_CORE_PROFILE_BIT_ARB, 0 };
    HGLRC rc = create ? create(dc, NULL, attribs) : NULL;
    fprintf(log, "core 4.4 context: %s\n", rc ? "ok" : "FAILED");
    if (!rc || !wglMakeCurrent(dc, rc)) { fclose(log); return 91; }
    fprintf(log, "GL_VENDOR: %s\nGL_RENDERER: %s\nGL_VERSION: %s\n",
            (const char *)glGetString(GL_VENDOR), (const char *)glGetString(GL_RENDERER), (const char *)glGetString(GL_VERSION));
    const char *glsl = (const char *)glGetString(0x8B8C);
    fprintf(log, "GLSL: %s\n", glsl ? glsl : "(null)");
    GLint n = 0, v = 0;
    glGetIntegerv(GL_NUM_EXTENSIONS, &n);
    fprintf(log, "GL_NUM_EXTENSIONS: %d, error 0x%x\n", n, glGetError());
    getstringi_t gsi = (getstringi_t)wglGetProcAddress("glGetStringi");
    for (GLint i = 0; gsi && i < n; i++) fprintf(log, "EXT %s\n", (const char *)gsi(GL_EXTENSIONS_I, i));
    glGetIntegerv(GL_MAX_TEXTURE_SIZE_, &v); fprintf(log, "GL_MAX_TEXTURE_SIZE: %d\n", v);
    static const struct { const char *n; GLenum e; } lim[] = {
        {"GL_MAX_TEXTURE_IMAGE_UNITS", 0x8872}, {"GL_MAX_VERTEX_ATTRIBS", 0x8869}, {"GL_MAX_DRAW_BUFFERS", 0x8824},
        {"GL_MAX_UNIFORM_BLOCK_SIZE", 0x8A30}, {"GL_MAX_SHADER_STORAGE_BLOCK_SIZE", 0x90DE},
        {"GL_MAX_COMPUTE_WORK_GROUP_INVOCATIONS", 0x90EB}, {"GL_MAX_SAMPLES", 0x8D57},
        {"GL_MAX_ARRAY_TEXTURE_LAYERS", 0x88FF}, {"GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS", 0x8B4D} };
    for (unsigned i = 0; i < sizeof lim / sizeof *lim; i++) { v = -1; glGetIntegerv(lim[i].e, &v); fprintf(log, "%s: %d\n", lim[i].n, v); }
    static const char *fns[] = { "glCreateTextures", "glNamedBufferStorage", "glBufferStorage", "glTextureStorage2D",
        "glMultiDrawElementsIndirect", "glClipControl", "glDispatchCompute", "glDebugMessageCallback", "glObjectLabel",
        "glGetTextureHandleARB", "glBindTextures", "glBindImageTextures", "glTexStorage3D", "glDrawElementsBaseVertex",
        "glProgramUniform1i", "glCreateProgramPipelines", "glMemoryBarrier", "glGetnUniformfv", "glInvalidateFramebuffer",
        "glCopyImageSubData", "glTextureView", "glFenceSync", "glQueryCounter", "glGetInteger64v", "glSwapIntervalEXT",
        "wglSwapIntervalEXT", "wglGetExtensionsStringARB", "wglChoosePixelFormatARB", "glGetInternalformativ" };
    for (unsigned i = 0; i < sizeof fns / sizeof *fns; i++) fprintf(log, "FN %s: %s\n", fns[i], wglGetProcAddress(fns[i]) ? "yes" : "NULL");
    fclose(log);
    return 0;
}
