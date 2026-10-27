/* A Windows program that plays a quiet tone on the default render device (WASAPI, shared mode) for a number of seconds, as a game
 * with no choice of device does, and logs once a second. Whether the sound follows a change of the default output device is seen
 * in the driver's trace (WINEDEBUG=+coreaudio: "output device A -> B") and heard. Argument: seconds (default 30).
 * Writes wasapi-follow.log in the current directory. */
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    FILE *log = fopen("wasapi-follow.log", "w");
    int seconds = argc > 1 ? atoi(argv[1]) : 30;
    IMMDeviceEnumerator *en = NULL;
    IMMDevice *dev = NULL;
    IAudioClient *client = NULL;
    IAudioRenderClient *render = NULL;
    WAVEFORMATEX *fmt = NULL;
    UINT32 frames = 0, pad = 0;
    double phase = 0;
    HRESULT hr;

    if (!log) return 90;
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &IID_IMMDeviceEnumerator, (void **)&en);
    fprintf(log, "enumerator %08lx\n", hr);
    if (FAILED(hr)) return 91;
    hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(en, eRender, eConsole, &dev);
    fprintf(log, "default endpoint %08lx\n", hr);
    if (FAILED(hr)) return 92;
    hr = IMMDevice_Activate(dev, &IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&client);
    if (FAILED(hr)) return 93;
    IAudioClient_GetMixFormat(client, &fmt);
    fprintf(log, "mix format %lu Hz, %u ch, %u bits\n", fmt->nSamplesPerSec, fmt->nChannels, fmt->wBitsPerSample);
    hr = IAudioClient_Initialize(client, AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, fmt, NULL);
    fprintf(log, "initialize %08lx\n", hr);
    if (FAILED(hr)) return 94;
    IAudioClient_GetBufferSize(client, &frames);
    IAudioClient_GetService(client, &IID_IAudioRenderClient, (void **)&render);
    IAudioClient_Start(client);
    for (int tick = 0; tick < seconds * 100; tick++) {
        BYTE *data;
        IAudioClient_GetCurrentPadding(client, &pad);
        UINT32 want = frames - pad;
        if (want && SUCCEEDED(IAudioRenderClient_GetBuffer(render, want, &data))) {
            float *f = (float *)data;   /* the mix format is float on Wine */
            for (UINT32 i = 0; i < want; i++) {
                float v = 0.03f * (float)sin(phase);
                phase += 2 * 3.14159265358979 * 440.0 / fmt->nSamplesPerSec;
                for (int c = 0; c < fmt->nChannels; c++) *f++ = v;
            }
            IAudioRenderClient_ReleaseBuffer(render, want, 0);
        }
        if (tick % 100 == 0) { fprintf(log, "t=%d padding %u of %u\n", tick / 100, pad, frames); fflush(log); }
        Sleep(10);
    }
    IAudioClient_Stop(client);
    fprintf(log, "done\n");
    fclose(log);
    return 0;
}
