// license:BSD-3-Clause
// copyright-holders:Bryan McPhail
/*************************************************************************

    Funky Jet

*************************************************************************/
#ifndef MAME_INCLUDES_FUNKYJET_H
#define MAME_INCLUDES_FUNKYJET_H

#pragma once

// mame
#include "machine/deco146.h"
#include "video/deco16ic.h"
#include "video/decospr.h"

// devices
#include "cpu/h6280/h6280.h"

// emu
#include "screen.h"


class funkyjet_state : public driver_device
{
public:
	funkyjet_state(const machine_config &mconfig, device_type type, const char *tag)
		: driver_device(mconfig, type, tag)
		, m_spriteram(*this, "spriteram")
		, m_pf_rowscroll(*this, "pf%u_rowscroll", 1)
		, m_screen(*this, "screen")
		, m_maincpu(*this, "maincpu")
		, m_audiocpu(*this, "audiocpu")
		, m_deco146(*this, "ioprot")
		, m_sprgen(*this, "spritegen")
		, m_deco_tilegen(*this, "tilegen")
	{ }

	void funkyjet(machine_config &config);

	void init_funkyjet();

private:
	// memory pointers
	required_shared_ptr<uint16_t> m_spriteram;
	required_shared_ptr_array<uint16_t, 2> m_pf_rowscroll;

	// devices
	required_device<screen_device> m_screen;
	required_device<cpu_device> m_maincpu;
	required_device<h6280_device> m_audiocpu;
	required_device<deco146_device> m_deco146;
	required_device<decospr_device> m_sprgen;
	required_device<deco16ic_device> m_deco_tilegen;

	uint32_t screen_update(screen_device &screen, bitmap_ind16 &bitmap, const rectangle &cliprect);

	uint16_t funkyjet_protection_region_0_146_r(offs_t offset);
	void funkyjet_protection_region_0_146_w(offs_t offset, uint16_t data, uint16_t mem_mask = ~0);
	void funkyjet_map(address_map &map);
	void sound_map(address_map &map);
};

#endif // MAME_INCLUDES_FUNKYJET_H
