/*
 * OSX Shared Buffer Video Output (extracted from mplayer's corevideo)
 *
 * This file is part of mplayer2.
 *
 * mplayer2 is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * mplayer2 is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with mplayer2.  If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * This video output was extracted from mplayer's corevideo. Its purpose is
 * to copy mp_image data to a shared buffer using mmap and to do simple
 * coordination with the GUIs using Distributed Objects.
 */


//#include <sys/mman.h>

#include "vo_sharedbuffer.h"
#include "vo.h"
#include "video/mp_image.h"

/*
#include "m_option.h"
#include "talloc.h"

#include "libmpcodecs/vfcap.h"
#include "libmpcodecs/mp_image.h"
#include "fastmemcpy.h"

#include "sub/sub.h"
#include "osd.h"
*/

// declarations
struct priv {
    char *buffer_name;
    unsigned char *image_data;
    uint32_t image_bytes;
    uint32_t image_width;
    uint32_t image_height;
    uint32_t image_format;
    uint32_t image_stride;
    uint32_t buffer_size;

	/*
    void (*vo_draw_alpha_fnc)(int w, int h, unsigned char* src,
        unsigned char *srca, int srcstride, unsigned char* dstbase,
        int dststride);
	*/

    NSDistantObject *mposx_proxy;
    id <MPlayerOSXVOProto> mposx_proto;
};


// implementation
/*
static void draw_alpha(void *ctx, int x0, int y0, int w, int h,
                            unsigned char *src, unsigned char *srca,
                            int stride)
{
    struct priv *p = ((struct vo *) ctx)->priv;
    p->vo_draw_alpha_fnc(w, h, src, srca, stride,
        p->image_data + (x0 + y0 * p->image_width) * p->image_bytespp,
        p->image_width * p->image_bytespp);
}
*/

/*
static unsigned int image_bytes(struct priv *p)
{
    printf("w: %d h: %d bytes: %d \n", p->image_width, p->image_height,  p->image_bytespp);
    return p->image_width * p->image_height * p->image_bytespp;
}
*/

static int preinit(struct vo *vo)
{
    MP_INFO(vo, "preinit \n");
    struct priv *p = vo->priv;
    //p->buffer_name = "mpv";
    return 0;
}

static void flip_page(struct vo *vo)
{
    //MP_INFO(vo, "flip_page \n");

    struct priv *p = vo->priv;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [p->mposx_proto render];
    [pool release];
}

//static void check_events(struct vo *vo) { }

static void draw_image(struct vo *vo, mp_image_t *mpi)
{
    //MP_INFO(vo, "draw_image \n");

    struct priv *p = vo->priv;
    memcpy_pic(p->image_data, mpi->planes[0],
               p->image_width * p->image_bytes, p->image_height,
               p->image_stride, mpi->stride[0]);
}

/*
static void draw_osd(struct vo *vo, struct osd_state *osd) {
    struct priv *p = vo->priv;
    osd_draw_text(osd, p->image_width, p->image_height, draw_alpha, vo);
}
*/

static void free_buffers(struct vo *vo)
{
    struct priv *p = vo->priv;
    [p->mposx_proto stop];
    p->mposx_proto = nil;
    [p->mposx_proxy release];
    p->mposx_proxy = nil;

    if (p->image_data) {
        if (munmap(p->image_data, p->buffer_size) == -1) {
            MP_FATAL(vo, "uninit: munmap failed. Error: %s\n", strerror(errno));
        }
        if (shm_unlink(p->buffer_name) == -1) {
            MP_FATAL(vo, "uninit: shm_unlink failed. Error: %s\n", strerror(errno));
        }
    }
}

/*
static int config(struct vo *vo, uint32_t width, uint32_t height,
                  uint32_t d_width, uint32_t d_height, uint32_t flags,
                  uint32_t format)
*/

static int reconfig(struct vo *vo, struct mp_image_params *params)
{
    MP_INFO(vo, "reconfig w: %d h: %d format: %d \n", params->w, params->h, params->imgfmt);

    struct priv *p = vo->priv;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    free_buffers(vo);

    p->image_width = params->w;
    p->image_height = params->h;
	p->image_format = params->imgfmt;

	switch (p->image_format)
	{
		case IMGFMT_RGB24:
			p->image_bytes = 3;
			break;
		case IMGFMT_RGB565:
			p->image_bytes = 2;
			break;
		case IMGFMT_420P:
			p->image_bytes = 1;
			break;
		case IMGFMT_NV12:
		case IMGFMT_UYVY:
			p->image_bytes = 2;
			break;
		default:
			p->image_bytes = 3;
	}
	p->image_stride = p->image_width * p->image_bytes;
	p->buffer_size = p->image_stride * p->image_height;

    MP_INFO(vo, "writing output to a shared buffer named \"%s\"\n", p->buffer_name);

    // create shared memory
    int shm_fd = shm_open(p->buffer_name, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
    if (shm_fd == -1) {
        MP_FATAL(vo, "failed to open shared memory. Error: %s\n", strerror(errno));
        goto err_out;
    }

    MP_INFO(vo, "dw: %d dh: %d\n", vo->dwidth, vo->dheight);
    MP_INFO(vo, "w: %d h: %d bytes: %d buffer size: %d\n", p->image_width, p->image_height, p->image_bytes, p->buffer_size);

    if (ftruncate(shm_fd, p->buffer_size) == -1) {
        close(shm_fd);
        shm_unlink(p->buffer_name);
        goto err_out;
    }

    p->image_data = mmap(NULL, p->buffer_size,
        PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
    close(shm_fd);

    if (p->image_data == MAP_FAILED) {
        MP_FATAL(vo, "failed to map shared memory. Error: %s\n", strerror(errno));
        shm_unlink(p->buffer_name);
        goto err_out;
    }

    //connect to mplayerosx
    p->mposx_proxy = [NSConnection
        rootProxyForConnectionWithRegisteredName:
                  [NSString stringWithUTF8String:p->buffer_name] host:nil];

    if ([p->mposx_proxy conformsToProtocol:@protocol(MPlayerOSXVOProto)]) {
        [p->mposx_proxy setProtocolForProxy:@protocol(MPlayerOSXVOProto)];
        p->mposx_proto = (id <MPlayerOSXVOProto>)p->mposx_proxy;
        [p->mposx_proto startWithWidth:p->image_width
                            withHeight:p->image_height
                             withBytes:p->image_bytes
                            withAspect:vo->dwidth*100/vo->dheight];
    } else {
        MP_ERR(vo, "distributed object doesn't conform to the correct protocol.\n");
        [p->mposx_proxy release];
        p->mposx_proxy = nil;
        p->mposx_proto = nil;
    }

    [pool release];
    return 0;
err_out:
    [pool release];
    return -1;
}

static int query_format(struct vo *vo, int format)
{
    //MP_INFO(vo, "query_format: %d \n", format);

    switch (format) {
    //case IMGFMT_YUY2:
    case IMGFMT_UYVY:
    case IMGFMT_RGB24:
    //case IMGFMT_ARGB:
    //case IMGFMT_BGRA:
        return 1;
    }
    return 0;
}

static void uninit(struct vo *vo)
{
    struct priv *p = vo->priv;
    free_buffers(vo);
}

static int control(struct vo *vo, uint32_t request, void *data)
{
    //MP_INFO(vo, "control: request: %d \n", request);

	/*
    struct priv *p = vo->priv;
    switch (request) {
        case VOCTRL_DRAW_IMAGE:
            return draw_image(vo, data);
        case VOCTRL_FULLSCREEN:
            [p->mposx_proto toggleFullscreen];
            return VO_TRUE;
        case VOCTRL_QUERY_FORMAT:
            return query_format(vo, *(uint32_t*)data);
        case VOCTRL_ONTOP:
            [p->mposx_proto ontop];
            return VO_TRUE;
    }
	*/
    return VO_NOTIMPL;
}


#undef OPT_BASE_STRUCT
#define OPT_BASE_STRUCT struct priv

const struct vo_driver video_out_sharedbuffer = {
    .name = "sharedbuffer",
    .description = "Mac OS X Shared Buffer (headless video output for GUIs)",
    .preinit = preinit,
    .reconfig = reconfig,
    .control = control,
    .flip_page = flip_page,
    .query_format = query_format,
    .draw_image = draw_image,
    //.check_events = check_events,
    .uninit = uninit,
    //.draw_osd = draw_osd,
    .priv_size = sizeof(struct priv),
	/*
    .options = (const struct m_option[]) {
        OPT_STRING("buffer_name", buffer_name, 0, OPTDEF_STR("mplayerosx")),
        {NULL},
    },
	*/
    .options = (const struct m_option[]) {
       {"buffer-name", OPT_STRING(buffer_name)},
       {0}
    },
    .priv_defaults = &(const struct priv) {
        .buffer_name = "mpv",
    },
    .options_prefix = "shm",
};
