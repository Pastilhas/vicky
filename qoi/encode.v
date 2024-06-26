module qoi

pub fn encode(data []u8, w u32, h u32, ch u8, cs u8) ![]u8 {
	if data.len != (w * h * u32(ch)) {
		return error('Invalid data size ${data.len} <> ${(w * h * u32(ch))}')
	}

	mut cfg := Config.new(w, h, ch, cs)!
	return cfg.encode(data)
}

fn (mut cfg Config) encode(data []u8) []u8 {
	// Write header
	cfg.write_32(magic)
	cfg.write_32(cfg.width)
	cfg.write_32(cfg.height)
	cfg.write_8(cfg.channels)
	cfg.write_8(cfg.colorspace)

	// Util vars
	data_len := cfg.width * cfg.height * u32(cfg.channels)
	data_end := data_len - u32(cfg.channels)
	mut pre_pix := Pixel{0, 0, 0, 0xff}
	mut index := [64]Pixel{}
	mut run := u8(0)

	// for each pixel
	for idx := 0; idx < data_len; idx += int(cfg.channels) {
		pix := Pixel.from(data, idx, cfg.channels)

		if pix.equals(pre_pix) { // if pixel is same as previous
			run += 1

			if run >= 62 || idx == data_end {
				cfg.write_8(op_run | (run - 1))
				run = 0
			}

			pre_pix = pix
			continue
		}

		if run > 0 { // if was in run write it
			cfg.write_8(op_run | (run - 1))
			run = 0
		}

		pos := pix.hash() % 64
		if index[pos].equals(pix) { // if pixel was found before
			cfg.write_8(op_index | u8(pos))
			pre_pix = pix
			continue
		}

		index[pos] = pix

		if pix.a == pre_pix.a {
			dr := int(pix.r) - pre_pix.r
			dg := int(pix.g) - pre_pix.g
			db := int(pix.b) - pre_pix.b

			dgr := dr - dg
			dgb := db - dg

			if dr > -3 && dr < 2 && dg > -3 && dg < 2 && db > -3 && db < 2 {
				v := u8(u8(dr + 2) << 4) | (u8(dg + 2) << 2) | u8(db + 2)
				cfg.write_8(op_diff | v)
			} else if dgr > -9 && dgr < 8 && dg > -33 && dg < 32 && dgb > -9 && dgb < 8 {
				cfg.write_8(op_luma | u8(dg + 32))
				cfg.write_8((u8(dgr + 8) << 4) | u8(dgb + 8))
			} else {
				cfg.write_8(op_rgb)
				cfg.write_8(pix.r)
				cfg.write_8(pix.g)
				cfg.write_8(pix.b)
			}
		} else {
			cfg.write_8(op_rgba)
			cfg.write_32(pix.rgba())
		}

		pre_pix = pix
	}

	for q in padding {
		cfg.write_8(q)
	}

	return cfg.bytes[..cfg.p]
}
