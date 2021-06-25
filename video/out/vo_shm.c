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

// Shared memory
#define DEFAULT_BUFFER_NAME "mpv"
static char * buffer_name;
static int shm_fd = 0;

// Image
static unsigned char * image_data;

static uint32_t image_width;
static uint32_t image_height;
static uint32_t image_bytes;
static uint32_t image_stride;
static uint32_t image_format;
static uint32_t frame_count = 0;
static uint32_t buffer_size = 0;
static uint32_t video_buffer_size = 0;

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

static int reconfig(struct vo *vo, struct mp_image_params *params)
{
    MP_INFO(vo, "reconfig w: %d h: %d format: %d \n", params->w, params->h, params->imgfmt);

	image_width = params->w;
	image_height = params->h;
	image_format = params->imgfmt;

	switch (image_format)
	{
		case IMGFMT_RGB24:
			image_bytes = 3;
			break;
		case IMGFMT_RGB565:
			image_bytes = 2;
			break;
		case IMGFMT_420P:
			image_bytes = 1;
			break;
		case IMGFMT_NV12:
		case IMGFMT_UYVY:
			image_bytes = 2;
			break;
		default:
			image_bytes = 3;
	}
	image_stride = image_width * image_bytes;
	video_buffer_size = image_stride * image_height;
	if (image_format == IMGFMT_420P) {
		video_buffer_size = image_width * image_height * 2;
	}

    return 0;
}

static void draw_image(struct vo *vo, mp_image_t *mpi)
{
    //MP_INFO(vo, "draw_image \n");
}

static void flip_page(struct vo *vo)
{
    //MP_INFO(vo, "flip_page \n");
}

static void uninit(struct vo *vo)
{
    MP_INFO(vo, "uninit \n");
}

static int preinit(struct vo *vo)
{
    MP_INFO(vo, "preinit \n");
	buffer_name = DEFAULT_BUFFER_NAME;
    return 0;
}

static int query_format(struct vo *vo, int format)
{
    //MP_INFO(vo, "query_format: %d \n", format);
    return format == IMGFMT_BGR24;
}

static int control(struct vo *vo, uint32_t request, void *data)
{
    //MP_INFO(vo, "control \n");
    switch (request) {
    }
    return VO_NOTIMPL;
}

const struct vo_driver video_out_shm = {
    .name = "shm",
    .description = "shm",
    .preinit = preinit,
    .query_format = query_format,
    .reconfig = reconfig,
    .control = control,
    .draw_image = draw_image,
    .flip_page = flip_page,
    .uninit = uninit,
    .priv_size = 0,
};
