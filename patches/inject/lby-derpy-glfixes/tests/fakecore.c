/* Stands in for WineMetalGL's core library: wmgl_get_pixel_formats fills the list as WineMetalGL 3.7.0 does. */
struct fmt { int draw_to_window, draw_to_pbuffer, double_buffer, stereo, color_bits, red_bits, green_bits, blue_bits, alpha_bits; };
unsigned wmgl_get_pixel_formats(struct fmt *f, unsigned max, unsigned *onscreen)
{
    unsigned n = 3;
    if (onscreen) *onscreen = n;
    for (unsigned i = 0; f && i < n && i < max; i++) {
        f[i] = (struct fmt){ 1, 0, 1, 0, 24, 8, 8, 8, 8 };
        if (i == 2) f[i] = (struct fmt){ 1, 0, 1, 0, 16, 5, 6, 5, 0 };   /* RGB565 stays 16 */
    }
    return n;
}
