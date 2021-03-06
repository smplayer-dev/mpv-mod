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


#include "vo_sharedbuffer.h"
#include "vo.h"
#include "video/mp_image.h"
#include "sub/osd.h"

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>


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

    NSDistantObject *mposx_proxy;
    id <MPlayerOSXVOProto> mposx_proto;
};


static int preinit(struct vo *vo)
{
    MP_INFO(vo, "preinit \n");
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

static void draw_image(struct vo *vo, mp_image_t *mpi)
{
    //MP_INFO(vo, "draw_image \n");

    struct priv *p = vo->priv;
    struct mp_osd_res dim = osd_res_from_image_params(vo->params);
    osd_draw_on_image(vo->osd, dim, mpi->pts, 0, mpi);

    if (p->image_format == IMGFMT_420P) {
        unsigned char * ptr = p->image_data;
        int size = p->image_stride * p->image_height;
        memcpy_pic(ptr, mpi->planes[0], p->image_width, p->image_height, p->image_stride, mpi->stride[0]);
        ptr += size;
        size = (p->image_width * p->image_height) / 2;
        memcpy_pic(ptr, mpi->planes[1], p->image_width / 2, p->image_height / 2, p->image_width / 2, mpi->stride[1]);
        ptr += size;
        memcpy_pic(ptr, mpi->planes[2], p->image_width / 2, p->image_height / 2, p->image_width / 2, mpi->stride[2]);
    } else {
        memcpy_pic(p->image_data, mpi->planes[0],
               p->image_width * p->image_bytes, p->image_height,
               p->image_stride, mpi->stride[0]);
    }
    talloc_free(mpi);
}

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
    if (p->image_format == IMGFMT_420P) {
        p->buffer_size = p->image_width * p->image_height * 2;
    }

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
    case IMGFMT_420P:
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
    free_buffers(vo);
}

static int control(struct vo *vo, uint32_t request, void *data)
{
    //MP_INFO(vo, "control: request: %d \n", request);
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
    .uninit = uninit,
    .priv_size = sizeof(struct priv),
    .options = (const struct m_option[]) {
       {"name", OPT_STRING(buffer_name)},
       {0}
    },
    .priv_defaults = &(const struct priv) {
        .buffer_name = "mpv",
    },
    .options_prefix = "sharedbuffer",
};
