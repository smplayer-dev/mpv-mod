/*
 * Shm video output driver
 * Copyright (c) 2021 Ricardo Villalba <ricardo@smplayer.info>
 * Copyright (c) 2005 Nicolas Plourde <nicolasplourde@gmail.com>
 *
 * This file is part of MPlayer.
 *
 * MPlayer is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * MPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with MPlayer; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

/* Based on vo_corevideo.m by Nicolas Plourde <nicolas.plourde@gmail.com> */

#include "vo.h"
#include "video/mp_image.h"
#include "sub/osd.h"

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>

// Shared memory
static int shm_fd = 0;

// Image
static unsigned char * image_data;

struct header_t {
	uint32_t header_size;
	uint32_t video_buffer_size;
	uint32_t width;
	uint32_t height;
	uint32_t bytes;
	uint32_t stride;
	uint32_t planes;
	uint32_t format;
	uint32_t frame_count;
	uint32_t busy;
	float fps;
} * header;


struct priv {
	char * buffer_name;
	uint32_t image_width;
	uint32_t image_height;
	uint32_t image_bytes;
	uint32_t image_stride;
	uint32_t image_format;
	uint32_t frame_count;
	uint32_t buffer_size;
	uint32_t video_buffer_size;
};

static void free_file_specific(struct vo *vo)
{
	struct priv * p = vo->priv;

	if (munmap(header, p->buffer_size) == -1) {
		MP_INFO(vo, "uninit: munmap failed. Error: %s\n", strerror(errno));
	}

	if (shm_unlink(p->buffer_name) == -1) {
		MP_INFO(vo, "uninit: shm_unlink failed. Error: %s\n", strerror(errno));
	}
}

static int reconfig(struct vo *vo, struct mp_image_params *params)
{
    MP_INFO(vo, "reconfig w: %d h: %d format: %d \n", params->w, params->h, params->imgfmt);

	free_file_specific(vo);

	struct priv * p = vo->priv;

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
	p->video_buffer_size = p->image_stride * p->image_height;
	if (p->image_format == IMGFMT_420P) {
		p->video_buffer_size = p->image_width * p->image_height * 2;
	}

	MP_INFO(vo, "w: %d h: %d format: %d\n", p->image_width, p->image_height, p->image_format);
	MP_INFO(vo, "stride: %d bytes: %d\n", p->image_stride, p->image_bytes);
	MP_INFO(vo, "video buffer size: %d\n", p->video_buffer_size);

	MP_INFO(vo, "writing output to a shared buffer named \"%s\"\n", p->buffer_name);

	// Create shared memory
	shm_fd = shm_open(p->buffer_name, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
	if (shm_fd == -1)
	{
		MP_FATAL(vo, "failed to open shared memory. Error: %s\n", strerror(errno));
		return -1;
	}

	p->buffer_size = sizeof(header) + p->video_buffer_size;

	if (ftruncate(shm_fd, p->buffer_size) == -1)
	{
		MP_FATAL(vo, "failed to size shared memory, possibly already in use. Error: %s\n", strerror(errno));
		close(shm_fd);
		shm_unlink(p->buffer_name);
		return -1;
	}

	header = mmap(NULL, p->buffer_size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
	close(shm_fd);

	if (header == MAP_FAILED)
	{
		MP_FATAL(vo, "failed to map shared memory. Error: %s\n", strerror(errno));
		shm_unlink(p->buffer_name);
		return 1;
	}

	header->header_size = sizeof(struct header_t);
	header->video_buffer_size = p->video_buffer_size;

	image_data = (unsigned char*) header + header->header_size;
	MP_INFO(vo, "header: %p image_data: %p\n", header, image_data);

    return 0;
}

static void draw_image(struct vo *vo, mp_image_t *mpi)
{
    //MP_INFO(vo, "draw_image \n");

	if (!mpi) {
		MP_WARN(vo, "no mpi \n");
		return;
	}

	struct priv * p = vo->priv;

	header->width = p->image_width;
	header->height = p->image_height;
	header->bytes = p->image_bytes;
	header->stride = p->image_stride;
	header->planes = mpi->num_planes;
	header->format = p->image_format;
	header->frame_count = p->frame_count++;
	header->fps = mpi->nominal_fps;

	switch (p->image_format) {
		case IMGFMT_420P: header->format = 808596553; break;
		case IMGFMT_UYVY: header->format = 1498831189; break;
		//case IMGFMT_NV12: header->format = 844715353; break;
		case IMGFMT_RGB24: header->format = 1380401688; break;
		//case IMGFMT_RGB565: header->format = 1380401680 ; break;
	}

	struct mp_osd_res dim = osd_res_from_image_params(vo->params);
	osd_draw_on_image(vo->osd, dim, mpi->pts, 0, mpi);

	//MP_INFO(vo, "w: %d h: %d stride: %d fps: %f \n", mpi->w, mpi->h, mpi->stride[0], mpi->nominal_fps);

	header->busy = 1;
	if (p->image_format == IMGFMT_420P) {
		unsigned char * ptr = image_data;
		int size = p->image_stride * p->image_height;
		memcpy_pic(ptr, mpi->planes[0], p->image_width, p->image_height, p->image_stride, mpi->stride[0]);
		ptr += size;
		size = (p->image_width * p->image_height) / 2;
		memcpy_pic(ptr, mpi->planes[1], p->image_width / 2, p->image_height / 2, p->image_width / 2, mpi->stride[1]);
		ptr += size;
		memcpy_pic(ptr, mpi->planes[2], p->image_width / 2, p->image_height / 2, p->image_width / 2, mpi->stride[2]);
	} else {
		memcpy_pic(image_data, mpi->planes[0], p->image_width * p->image_bytes, p->image_height, p->image_stride, mpi->stride[0]);
	}
	header->busy = 0;
}

static void flip_page(struct vo *vo)
{
    //MP_INFO(vo, "flip_page \n");
}

static void uninit(struct vo *vo)
{
    MP_INFO(vo, "uninit \n");
	free_file_specific(vo);
}

static int preinit(struct vo *vo)
{
    MP_INFO(vo, "preinit \n");
	struct priv * p = vo->priv;
	MP_INFO(vo, "preinit: buffer_name: %s \n", p->buffer_name);
	/*
	if (p->buffer_name) {
		buffer_name = strdup( p->buffer_name);
	} else {
		buffer_name = DEFAULT_BUFFER_NAME;
	}
	*/
    return 0;
}

static int query_format(struct vo *vo, int format)
{
    //MP_INFO(vo, "query_format: %d \n", format);
    switch(format)
	{
		case IMGFMT_420P:
		//case IMGFMT_NV12:
		case IMGFMT_UYVY:
		case IMGFMT_RGB24:
		//case IMGFMT_RGB565:
			return 1;
    }

    return 0;
}

static int control(struct vo *vo, uint32_t request, void *data)
{
    //MP_INFO(vo, "control \n");
    return VO_NOTIMPL;
}

#define OPT_BASE_STRUCT struct priv

const struct vo_driver video_out_shm = {
    .name = "shm",
    .description = "Shared buffer",
    .preinit = preinit,
    .query_format = query_format,
    .reconfig = reconfig,
    .control = control,
    .draw_image = draw_image,
    .flip_page = flip_page,
    .uninit = uninit,
    .priv_size = sizeof(struct priv),
    .options = (const struct m_option[]) {
       {"buffer-name", OPT_STRING(buffer_name)},
       {0}
    },
    .priv_defaults = &(const struct priv) {
        .buffer_name = "mpv",
    },
    .options_prefix = "shm",
};
