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

static int reconfig(struct vo *vo, struct mp_image_params *params)
{
    MP_INFO(vo, "reconfig \n");

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
