// Copyright 2023 %YOUR_FULL_NAME% (@%YOUR_GITHUB_USERNAME%)
// SPDX-License-Identifier: GPL-2.0-or-later

#include QMK_KEYBOARD_H
#ifdef MOUSEKEY_ENABLE
#    include "mousekey.h"
#endif

enum blender_keycode {
    K_RGBI1 = SAFE_RANGE,
    K_RGBI0,
    K_RGBIT,
    K_RSnd1,
    K_RSnd0,
    K_RsndT,
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [0] = LAYOUT(
        KC_ESC,         KC_F1,  KC_F2,  KC_F3,  KC_F4,  KC_F5,  KC_F6,  KC_F7,  KC_F8,  KC_F9,  KC_F10, KC_F11, KC_F12, KC_INS, KC_HOME,KC_PGUP,KC_PSCR,
                                                                                                                        KC_DEL, KC_END, KC_PGDN,KC_SCRL,
        KC_GRV, KC_1,   KC_2,   KC_3,   KC_4,   KC_5,   KC_6,   KC_7,   KC_8,   KC_9,   KC_0,   KC_MINS,KC_EQL, KC_BSPC,KC_NUM, KC_PSLS,KC_PAST,KC_PAUS,
        KC_TAB, KC_Q,   KC_W,   KC_E,   KC_R,   KC_T,   KC_Y,   KC_U,   KC_I,   KC_O,   KC_P,   KC_LBRC,KC_RBRC,KC_ENT, KC_P7,  KC_P8,  KC_P9,  KC_PMNS,
        KC_CAPS,KC_A,   KC_S,   KC_D,   KC_F,   KC_G,   KC_H,   KC_J,   KC_K,   KC_L,   KC_SCLN,        KC_QUOT,KC_NUHS,KC_P4,  KC_P5,  KC_P6,  KC_PPLS,
        KC_LSFT,KC_LGUI,KC_Z,   KC_X,   KC_C,   KC_V,   KC_B,   KC_N,   KC_M,   KC_COMM,KC_DOT, KC_SLSH,KC_RSFT,KC_UP,  KC_P1,  KC_P2,  KC_P3,  KC_PENT,
        KC_LCTL,KC_LALT,                                        KC_SPC,         MO(1),          KC_RCTL,KC_LEFT,KC_DOWN,KC_RGHT,KC_P0,  KC_PDOT,
        MS_BTN1,MS_BTN2
    ),
    [1] = LAYOUT(
        _______,        _______,_______, _______,_______,_______,_______,_______,_______,_______,_______,_______,_______,HF_TOGG,HF_ON,  HF_OFF, _______,
                                                                                                                        HF_BUZZ,HF_CONT,HF_DWLU,_______,
		_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,HF_FDBK,HF_RST, HF_DWLD,_______,
		_______,K_RGBIT,K_RsndT,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,
		_______,RM_TOGG,RM_NEXT,RM_HUEU,RM_HUED,RM_SATU,RM_SATD,RM_VALU,RM_VALD,_______,_______,        _______,_______,_______,_______,_______,_______,
		_______,_______,UG_TOGG,UG_VALU,UG_VALD,UG_NEXT,_______,_______,_______,_______,_______,_______,RM_TOGG,CK_UP,  _______,_______,_______,_______,
		_______,_______,                                        _______,        _______,        _______,CK_TOGG,CK_DOWN,CK_RST, _______,_______,
        _______,_______
    ),
    [2] = LAYOUT(
        _______,        _______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,
                                                                                                                        _______,_______,_______,_______,
		_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,
		_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,
		_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,        _______,_______,_______,_______,_______,_______,
		_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,
		_______,_______,                                        _______,        _______,        _______,_______,_______,_______,_______,_______,
        _______,_______
    )
};

typedef union {
  uint32_t raw;
  struct {
    bool flag_rgb_indicator;
    bool flag_rgb_sound;
  };
} user_config_rgb_t;

user_config_rgb_t kb_storage;

void eeconfig_init_user(void) {  // EEPROM is getting reset!
    kb_storage.flag_rgb_indicator = true;
    kb_storage.flag_rgb_sound     = true; // We want this enabled by default
    eeconfig_update_user(kb_storage.raw); // Write default value to EEPROM now
}

void keyboard_post_init_user(void) {
  // Call the keymap level matrix init.

  // Read the user config from EEPROM
    kb_storage.raw = eeconfig_read_user();

}

bool is_keyboard_left(void) {
    return true;
}

#if defined(MOUSEKEY_ENABLE) && defined(PS2_MOUSE_ENABLE)
static bool handle_ps2_mouse_button_keycode(uint16_t keycode, keyrecord_t *record) {
    if (keycode < QK_MOUSE_BUTTON_1 || keycode > QK_MOUSE_BUTTON_3) {
        return false;
    }

    extern int tp_buttons;

    if (record->event.pressed) {
        mousekey_on((uint8_t)keycode);
        tp_buttons |= MOUSE_BTN_MASK(keycode - QK_MOUSE_BUTTON_1);
    } else {
        mousekey_off((uint8_t)keycode);
        tp_buttons &= ~MOUSE_BTN_MASK(keycode - QK_MOUSE_BUTTON_1);
    }

    mousekey_send();
    return true;
}
#endif

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
#if defined(MOUSEKEY_ENABLE) && defined(PS2_MOUSE_ENABLE)
    if (handle_ps2_mouse_button_keycode(keycode, record)) {
        return false;
    }
#endif

    switch (keycode) {
        case K_RGBI1:
            if (record->event.pressed) {
                kb_storage.flag_rgb_indicator = true;
                eeconfig_update_user(kb_storage.raw);
            } else {
            }
            break;
        case K_RGBI0:
            if (record->event.pressed) {
                kb_storage.flag_rgb_indicator = false;
                eeconfig_update_user(kb_storage.raw);
            } else {
            }
            break;
        case K_RGBIT:
            if (record->event.pressed) {
                kb_storage.flag_rgb_indicator = !kb_storage.flag_rgb_indicator;
                eeconfig_update_user(kb_storage.raw);
            } else {
            }
            break;
        case K_RSnd1:
            if (record->event.pressed) {
                kb_storage.flag_rgb_sound = true;
                eeconfig_update_user(kb_storage.raw);
            } else {
            }
            break;
        case K_RSnd0:
            if (record->event.pressed) {
                kb_storage.flag_rgb_sound = false;
                eeconfig_update_user(kb_storage.raw);
            } else {
            }
            break;
        case K_RsndT:
            if (record->event.pressed) {
                kb_storage.flag_rgb_sound = !kb_storage.flag_rgb_sound;
                eeconfig_update_user(kb_storage.raw);
            } else {
            }
            break;
    };
    return true;
};

#if defined(ENCODER_MAP_ENABLE)
const uint16_t PROGMEM encoder_map[][NUM_ENCODERS][NUM_DIRECTIONS] = {
    [0] = { ENCODER_CCW_CW(KC_VOLD, KC_VOLU)  },
    [1] = { ENCODER_CCW_CW(MS_WHLU, MS_WHLD)  },
    [2] = { ENCODER_CCW_CW(KC_DOWN, KC_UP)    }
};
#endif

int last_volume = 0;

bool rgb_matrix_indicators_advanced_user(uint8_t led_min, uint8_t led_max) {
    if (kb_storage.flag_rgb_sound) {
        switch(last_volume) {
            case 12: rgb_matrix_set_color( 8, 96, 0, 0);
            case 11: rgb_matrix_set_color( 9, 96, 0, 0);
            case 10: rgb_matrix_set_color(10, 128, 128, 0);
            case  9: rgb_matrix_set_color(11, 128, 128, 0);
            case  8: rgb_matrix_set_color(12, 0, 96, 0);
            case  7: rgb_matrix_set_color(13, 0, 96, 0);
            case  6: rgb_matrix_set_color(14, 0, 96, 0);
            case  5: rgb_matrix_set_color(15, 0, 96, 0);
            case  4: rgb_matrix_set_color(16, 0, 96, 0);
            case  3: rgb_matrix_set_color(17, 0, 96, 0);
            case  2: rgb_matrix_set_color(18, 0, 96, 0);
            case  1: rgb_matrix_set_color(19, 0, 96, 0);
        }
    }

    if (kb_storage.flag_rgb_indicator) {
        if (host_keyboard_led_state().scroll_lock) {
            rgb_matrix_set_color(3, 0x7F, 0xFF, 0x00);
        }
        if (host_keyboard_led_state().caps_lock) {
            rgb_matrix_set_color(57, 0x7F, 0xFF, 0x00);
        }
        if (host_keyboard_led_state().num_lock) {
            rgb_matrix_set_color(35, 0x7F, 0xFF, 0x00);
        }
    }

    if (host_keyboard_led_state().scroll_lock) {
        rgb_matrix_set_color(102, 0x7F, 0xFF, 0x00);
    }
    else {
        rgb_matrix_set_color(102, 0x00, 0x00, 0x00);
    }
    if (host_keyboard_led_state().caps_lock) {
        rgb_matrix_set_color(103, 0x7F, 0xFF, 0x00);
    }
    else {
        rgb_matrix_set_color(103, 0x00, 0x00, 0x00);
    }
    if (host_keyboard_led_state().num_lock) {
        rgb_matrix_set_color(104, 0x7F, 0xFF, 0x00);
    }
    else {
        rgb_matrix_set_color(104, 0x00, 0x00, 0x00);
    }
    return false;
}
