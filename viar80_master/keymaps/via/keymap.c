// Copyright 2023 %YOUR_FULL_NAME% (@%YOUR_GITHUB_USERNAME%)
// SPDX-License-Identifier: GPL-2.0-or-later

#include QMK_KEYBOARD_H
#ifdef PS2_MOUSE_ENABLE
#    include "ps2.h"
#    include "ps2_mouse.h"
#endif
#ifdef MOUSEKEY_ENABLE
#    include "mousekey.h"
#endif
#include "analog.h"
#include "gpio.h"
#include "ch.h"
#ifdef AUDIO_ENABLE
#    include "audio.h"
#    ifdef AUDIO_CLICKY
#        include "process_clicky.h"
#    endif
#endif
#ifdef BATTERY_ENABLE
#    include "battery.h"
#endif
#ifdef HAPTIC_ENABLE
#    include "haptic.h"
extern haptic_config_t haptic_config;
#endif
#ifdef OLED_ENABLE
#    include <string.h>
#    include "oled_assets.generated.h"
#endif

#if defined(AUDIO_ENABLE) && defined(AUDIO_CLICKY)
extern float clicky_freq;
#endif

enum blender_keycode {
    K_RGBI1 = SAFE_RANGE,
    K_RGBI0,
    K_RGBIT,
    K_RSnd1,
    K_RSnd0,
    K_RsndT,
    K_TPTOG,
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
        _______,K_RGBIT,K_RsndT,_______,_______,K_TPTOG,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,_______,
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

bool is_keyboard_left(void) {
    return false;
}

typedef union {
  uint32_t raw;
  struct {
    uint8_t flag_rgb_indicator : 1;
    uint8_t flag_rgb_sound     : 1;
    uint8_t connection_mode    : 2;
  };
} user_config_rgb_t;

user_config_rgb_t kb_storage;
static bool encoder_button_raw        = false;
static bool encoder_button_stable     = false;
static bool encoder_is_muted          = false;
static bool trackpoint_enabled        = true;
static uint16_t encoder_button_timer  = 0;
static uint16_t encoder_led_red_level = 0;
static uint16_t encoder_led_green_level = 0;
static uint16_t encoder_led_red_target = 0;
static uint16_t encoder_led_green_target = 0;
static uint32_t oled_boot_timer       = 0;
static uint32_t last_keypress_timer   = 0;
static uint32_t last_encoder_timer    = 0;
static uint32_t encoder_led_effect_timer = 0;
static uint32_t encoder_led_fade_timer = 0;
static bool encoder_last_clockwise    = true;
static bool encoder_led_pwm_initialized = false;

typedef struct {
    pin_t    pin;
    uint16_t active_on_threshold;
    uint16_t active_off_threshold;
    uint16_t raw_value;
    bool     active;
    bool     pending_active;
    uint8_t  stable_samples;
    uint32_t last_sample;
    uint32_t last_change;
    uint32_t last_blink_edge;
} wireless_status_input_t;

typedef enum {
    WIRELESS_CHARGE_STATE_UNKNOWN = 0,
    WIRELESS_CHARGE_STATE_NORMAL,
    WIRELESS_CHARGE_STATE_LOW,
    WIRELESS_CHARGE_STATE_CHARGING,
    WIRELESS_CHARGE_STATE_FULL,
} wireless_charge_state_t;

typedef enum {
    WIRELESS_LED_COLOR_NONE = 0,
    WIRELESS_LED_COLOR_RED,
    WIRELESS_LED_COLOR_BLUE,
} wireless_led_color_t;

typedef enum {
    CONNECTION_MODE_USB = 0,
    CONNECTION_MODE_BLUETOOTH,
    CONNECTION_MODE_24G,
} connection_mode_t;

typedef struct {
    bool     valid;
    uint16_t year;
    uint8_t  month;
    uint8_t  day;
    uint8_t  hour;
    uint8_t  minute;
    uint8_t  second;
    uint32_t last_tick;
} local_clock_t;

typedef struct {
    bool     receiving;
    uint8_t  preamble_index;
    uint8_t  received_symbols;
    uint8_t  last_led_raw;
    uint32_t payload;
    uint32_t last_symbol_time;
} lock_time_sync_t;

static wireless_status_input_t wireless_power_red  = {
    .pin                  = WIRELESS_POWER_LED_RED_PIN,
    .active_on_threshold  = 120,
    .active_off_threshold = 60,
};
static wireless_status_input_t wireless_power_blue = {
    .pin                  = WIRELESS_POWER_LED_BLUE_PIN,
    .active_on_threshold  = 120,
    .active_off_threshold = 60,
};
static connection_mode_t connection_mode = CONNECTION_MODE_USB;
static uint8_t connection_hotkey_mods = 0;
static wireless_led_color_t wireless_visible_color = WIRELESS_LED_COLOR_NONE;
static uint32_t wireless_visible_color_timer = 0;
static local_clock_t local_clock = {0};
static lock_time_sync_t lock_time_sync = {0};

#define ENCODER_LED_PWM_FREQUENCY      1000000
#define ENCODER_LED_PWM_PERIOD             255
#define ENCODER_LED_ACTIVE_BRIGHTNESS    255
#define ENCODER_LED_GREEN_IDLE_BRIGHTNESS 48
#define ENCODER_LED_RED_IDLE_BRIGHTNESS  160
#define ENCODER_LED_EFFECT_MS            180
#define ENCODER_LED_FADE_INTERVAL_MS      12
#define ENCODER_LED_FADE_STEP             16
#define WIRELESS_LED_SAMPLE_MS            50
#define WIRELESS_LED_STABLE_SAMPLES         3
#define WIRELESS_LED_MIN_BLINK_MS        150
#define WIRELESS_LED_MAX_BLINK_MS       1500
#define WIRELESS_LED_BLINK_HOLD_MS      1600
#define WIRELESS_LED_COLOR_HOLD_MS      1300
#define WIRELESS_LED_DOMINANT_MARGIN      30
#define LOCAL_CLOCK_DEFAULT_YEAR        2026
#define LOCAL_CLOCK_DEFAULT_MONTH          1
#define LOCAL_CLOCK_DEFAULT_DAY            1
#define LOCAL_CLOCK_TIME_VALUE_ID       0x10
#define LOCAL_CLOCK_DATETIME_VALUE_ID   0x11
#define LOCK_TIME_SYNC_MIN_SYMBOL_MS     40
#define LOCK_TIME_SYNC_MAX_SYMBOL_MS    220
#define LOCK_TIME_SYNC_PREAMBLE_LENGTH    4
#define LOCK_TIME_SYNC_PAYLOAD_SYMBOLS   16

static PWMConfig encoder_led_tim2_cfg = {
    .frequency = ENCODER_LED_PWM_FREQUENCY,
    .period    = ENCODER_LED_PWM_PERIOD,
};

static PWMConfig encoder_led_tim3_cfg = {
    .frequency = ENCODER_LED_PWM_FREQUENCY,
    .period    = ENCODER_LED_PWM_PERIOD,
};

static uint16_t encoder_led_step_toward(uint16_t current, uint16_t target) {
    if (current == target) {
        return current;
    }

    if (current < target) {
        const uint16_t next = current + ENCODER_LED_FADE_STEP;
        return next > target ? target : next;
    }

    return current > ENCODER_LED_FADE_STEP + target ? current - ENCODER_LED_FADE_STEP : target;
}

static void encoder_led_note_activity(void) {
    encoder_led_effect_timer = timer_read32();
}

static void encoder_led_update_targets(void) {
    const bool boost = timer_elapsed32(encoder_led_effect_timer) < ENCODER_LED_EFFECT_MS;

    encoder_led_red_target   = encoder_is_muted ? (boost ? ENCODER_LED_ACTIVE_BRIGHTNESS : ENCODER_LED_RED_IDLE_BRIGHTNESS) : 0;
    encoder_led_green_target = encoder_is_muted ? 0 : (boost ? ENCODER_LED_ACTIVE_BRIGHTNESS : ENCODER_LED_GREEN_IDLE_BRIGHTNESS);
}

static void encoder_led_init_pwm(void) {
    if (encoder_led_pwm_initialized) {
        return;
    }

    encoder_led_tim2_cfg.channels[3].mode = PWM_OUTPUT_ACTIVE_LOW;
    encoder_led_tim3_cfg.channels[0].mode = PWM_OUTPUT_ACTIVE_LOW;

    palSetLineMode(ENCODER_LED_RED_PIN, PAL_MODE_STM32_ALTERNATE_OPENDRAIN);
    palSetLineMode(ENCODER_LED_GREEN_PIN, PAL_MODE_STM32_ALTERNATE_OPENDRAIN);
    gpio_set_pin_input_high(ENCODER_LED_BLUE_PIN);

    pwmStart(&PWMD2, &encoder_led_tim2_cfg);
    pwmStart(&PWMD3, &encoder_led_tim3_cfg);

    encoder_led_pwm_initialized = true;
}

static void encoder_led_apply_level(PWMDriver *driver, pwmchannel_t channel, uint16_t level) {
    pwmEnableChannel(driver, channel, PWM_FRACTION_TO_WIDTH(driver, ENCODER_LED_PWM_PERIOD, level));
}

static void set_encoder_led_state(bool immediate) {
    encoder_led_update_targets();

    if (immediate) {
        encoder_led_red_level   = encoder_led_red_target;
        encoder_led_green_level = encoder_led_green_target;
    }

    encoder_led_init_pwm();
    encoder_led_apply_level(&PWMD2, 3, encoder_led_red_level);
    encoder_led_apply_level(&PWMD3, 0, encoder_led_green_level);
    gpio_set_pin_input_high(ENCODER_LED_BLUE_PIN);
}

static void encoder_led_task(void) {
    encoder_led_update_targets();

    if (timer_elapsed32(encoder_led_fade_timer) >= ENCODER_LED_FADE_INTERVAL_MS) {
        encoder_led_red_level   = encoder_led_step_toward(encoder_led_red_level, encoder_led_red_target);
        encoder_led_green_level = encoder_led_step_toward(encoder_led_green_level, encoder_led_green_target);
        encoder_led_fade_timer  = timer_read32();
    }

    set_encoder_led_state(false);
}

static void wireless_status_input_init(wireless_status_input_t *input) {
    input->raw_value       = analogReadPin(input->pin);
    input->active          = input->raw_value >= input->active_on_threshold;
    input->pending_active  = input->active;
    input->stable_samples  = 0;
    input->last_sample     = timer_read32();
    input->last_change     = input->last_sample;
    input->last_blink_edge = 0;
}

static void wireless_status_input_task(wireless_status_input_t *input) {
    const uint32_t now = timer_read32();

    if (timer_elapsed32(input->last_sample) < WIRELESS_LED_SAMPLE_MS) {
        return;
    }

    input->last_sample = now;
    input->raw_value   = analogReadPin(input->pin);

    bool sampled_active = input->active;

    if (input->active) {
        if (input->raw_value <= input->active_off_threshold) {
            sampled_active = false;
        }
    } else if (input->raw_value >= input->active_on_threshold) {
        sampled_active = true;
    }

    if (sampled_active != input->pending_active) {
        input->pending_active = sampled_active;
        input->stable_samples = 1;
        return;
    }

    if (sampled_active == input->active) {
        input->stable_samples = 0;
        return;
    }

    if (++input->stable_samples < WIRELESS_LED_STABLE_SAMPLES) {
        return;
    }

    const uint32_t interval = timer_elapsed32(input->last_change);

    input->active         = sampled_active;
    input->stable_samples = 0;
    input->last_change    = now;

    if (interval >= WIRELESS_LED_MIN_BLINK_MS && interval <= WIRELESS_LED_MAX_BLINK_MS) {
        input->last_blink_edge = now;
    }
}

static bool wireless_status_input_is_blinking(const wireless_status_input_t *input) {
    return input->last_blink_edge != 0 && timer_elapsed32(input->last_blink_edge) < WIRELESS_LED_BLINK_HOLD_MS;
}

static wireless_led_color_t wireless_get_current_color(void) {
    if (wireless_power_red.active && wireless_power_blue.active) {
        if (wireless_power_red.raw_value >= wireless_power_blue.raw_value + WIRELESS_LED_DOMINANT_MARGIN) {
            return WIRELESS_LED_COLOR_RED;
        }
        if (wireless_power_blue.raw_value >= wireless_power_red.raw_value + WIRELESS_LED_DOMINANT_MARGIN) {
            return WIRELESS_LED_COLOR_BLUE;
        }
        return wireless_power_red.raw_value >= wireless_power_blue.raw_value ? WIRELESS_LED_COLOR_RED : WIRELESS_LED_COLOR_BLUE;
    }

    if (wireless_power_red.active) {
        return WIRELESS_LED_COLOR_RED;
    }

    if (wireless_power_blue.active) {
        return WIRELESS_LED_COLOR_BLUE;
    }

    return WIRELESS_LED_COLOR_NONE;
}

static void wireless_visible_color_task(void) {
    const wireless_led_color_t current_color = wireless_get_current_color();

    if (current_color != WIRELESS_LED_COLOR_NONE) {
        wireless_visible_color       = current_color;
        wireless_visible_color_timer = timer_read32();
    } else if (timer_elapsed32(wireless_visible_color_timer) >= WIRELESS_LED_COLOR_HOLD_MS) {
        wireless_visible_color = WIRELESS_LED_COLOR_NONE;
    }
}

static wireless_charge_state_t wireless_get_charge_state(void) {
    if (wireless_status_input_is_blinking(&wireless_power_red)) {
        return WIRELESS_CHARGE_STATE_CHARGING;
    }

    if (wireless_status_input_is_blinking(&wireless_power_blue)) {
        return WIRELESS_CHARGE_STATE_LOW;
    }

    switch (wireless_visible_color) {
        case WIRELESS_LED_COLOR_RED:
            return WIRELESS_CHARGE_STATE_CHARGING;
        case WIRELESS_LED_COLOR_BLUE:
            return wireless_status_input_is_blinking(&wireless_power_blue) ? WIRELESS_CHARGE_STATE_LOW : WIRELESS_CHARGE_STATE_NORMAL;
        case WIRELESS_LED_COLOR_NONE:
        default:
            break;
    }

    return WIRELESS_CHARGE_STATE_UNKNOWN;
}

static bool local_clock_is_leap_year(uint16_t year) {
    if ((year % 400) == 0) {
        return true;
    }

    if ((year % 100) == 0) {
        return false;
    }

    return (year % 4) == 0;
}

static uint8_t local_clock_days_in_month(uint16_t year, uint8_t month) {
    static const uint8_t days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

    if (month < 1 || month > 12) {
        return 31;
    }

    if (month == 2 && local_clock_is_leap_year(year)) {
        return 29;
    }

    return days[month - 1];
}

static bool local_clock_set_datetime(uint16_t year, uint8_t month, uint8_t day, uint8_t hour, uint8_t minute, uint8_t second) {
    if (month < 1 || month > 12) {
        return false;
    }

    if (day < 1 || day > local_clock_days_in_month(year, month)) {
        return false;
    }

    if (hour > 23 || minute > 59 || second > 59) {
        return false;
    }

    local_clock.valid     = true;
    local_clock.year      = year;
    local_clock.month     = month;
    local_clock.day       = day;
    local_clock.hour      = hour;
    local_clock.minute    = minute;
    local_clock.second    = second;
    local_clock.last_tick = timer_read32();
    return true;
}

static bool local_clock_set_time(uint8_t hour, uint8_t minute, uint8_t second) {
    return local_clock_set_datetime(
        local_clock.valid ? local_clock.year : LOCAL_CLOCK_DEFAULT_YEAR,
        local_clock.valid ? local_clock.month : LOCAL_CLOCK_DEFAULT_MONTH,
        local_clock.valid ? local_clock.day : LOCAL_CLOCK_DEFAULT_DAY,
        hour,
        minute,
        second
    );
}

static void local_clock_advance_one_second(void) {
    if (!local_clock.valid) {
        return;
    }

    if (++local_clock.second < 60) {
        return;
    }

    local_clock.second = 0;
    if (++local_clock.minute < 60) {
        return;
    }

    local_clock.minute = 0;
    if (++local_clock.hour < 24) {
        return;
    }

    local_clock.hour = 0;
    if (++local_clock.day <= local_clock_days_in_month(local_clock.year, local_clock.month)) {
        return;
    }

    local_clock.day = 1;
    if (++local_clock.month <= 12) {
        return;
    }

    local_clock.month = 1;
    local_clock.year++;
}

static void local_clock_task(void) {
    if (!local_clock.valid) {
        local_clock.last_tick = timer_read32();
        return;
    }

    while (timer_elapsed32(local_clock.last_tick) >= 1000) {
        local_clock.last_tick += 1000;
        local_clock_advance_one_second();
    }
}

static void lock_time_sync_reset(void) {
    lock_time_sync.receiving        = false;
    lock_time_sync.preamble_index   = 0;
    lock_time_sync.received_symbols = 0;
    lock_time_sync.payload          = 0;
}

static bool lock_time_sync_apply_payload(uint32_t payload) {
    const uint16_t year   = 2000 + ((payload >> 26) & 0x3F);
    const uint8_t  month  = (payload >> 22) & 0x0F;
    const uint8_t  day    = (payload >> 17) & 0x1F;
    const uint8_t  hour   = (payload >> 12) & 0x1F;
    const uint8_t  minute = (payload >> 6) & 0x3F;
    const uint8_t  second = payload & 0x3F;

    return local_clock_set_datetime(year, month, day, hour, minute, second);
}

static void lock_time_sync_begin_payload(uint32_t now) {
    lock_time_sync.receiving        = true;
    lock_time_sync.preamble_index   = 0;
    lock_time_sync.received_symbols = 0;
    lock_time_sync.payload          = 0;
    lock_time_sync.last_symbol_time = now;
}

static void lock_time_sync_process_symbol(uint8_t symbol, uint32_t now) {
    const bool has_previous = lock_time_sync.last_symbol_time != 0;
    const uint32_t interval = has_previous ? timer_elapsed32(lock_time_sync.last_symbol_time) : 0;
    const bool interval_valid = !has_previous || (interval >= LOCK_TIME_SYNC_MIN_SYMBOL_MS && interval <= LOCK_TIME_SYNC_MAX_SYMBOL_MS);

    if (lock_time_sync.receiving) {
        if (!interval_valid) {
            lock_time_sync_reset();
        } else {
            lock_time_sync.payload = (lock_time_sync.payload << 2) | (symbol & 0x03);
            lock_time_sync.received_symbols++;
            lock_time_sync.last_symbol_time = now;

            if (lock_time_sync.received_symbols >= LOCK_TIME_SYNC_PAYLOAD_SYMBOLS) {
                if (lock_time_sync_apply_payload(lock_time_sync.payload)) {
                    last_keypress_timer = timer_read32();
                }
                lock_time_sync_reset();
            }
            return;
        }
    }

    if (!interval_valid) {
        lock_time_sync.preamble_index = (symbol == 0) ? 1 : 0;
        lock_time_sync.last_symbol_time = now;
        return;
    }

    if (lock_time_sync.preamble_index == 0) {
        lock_time_sync.preamble_index = (symbol == 0) ? 1 : 0;
        lock_time_sync.last_symbol_time = now;
        return;
    }

    if (symbol == lock_time_sync.preamble_index) {
        lock_time_sync.preamble_index++;
        if (lock_time_sync.preamble_index >= LOCK_TIME_SYNC_PREAMBLE_LENGTH) {
            lock_time_sync_begin_payload(now);
            return;
        }
    } else {
        lock_time_sync.preamble_index = (symbol == 0) ? 1 : 0;
    }

    lock_time_sync.last_symbol_time = now;
}

static void lock_time_sync_handle_led_state(led_t led_state) {
    const uint8_t previous_raw = lock_time_sync.last_led_raw;
    const bool scroll_changed = ((previous_raw ^ led_state.raw) & (1 << 2)) != 0;

    lock_time_sync.last_led_raw = led_state.raw;

    if (!scroll_changed) {
        return;
    }

    lock_time_sync_process_symbol((led_state.caps_lock ? 0x02 : 0x00) | (led_state.num_lock ? 0x01 : 0x00), timer_read32());
}

static void update_connection_mode_from_hotkey(uint16_t keycode, bool pressed) {
    switch (keycode) {
        case KC_LCTL:
        case KC_RCTL:
            if (pressed) {
                connection_hotkey_mods |= MOD_MASK_CTRL;
            } else {
                connection_hotkey_mods &= ~MOD_MASK_CTRL;
            }
            return;
        case KC_LALT:
        case KC_RALT:
            if (pressed) {
                connection_hotkey_mods |= MOD_MASK_ALT;
            } else {
                connection_hotkey_mods &= ~MOD_MASK_ALT;
            }
            return;
        case KC_LSFT:
        case KC_RSFT:
            if (pressed) {
                connection_hotkey_mods |= MOD_MASK_SHIFT;
            } else {
                connection_hotkey_mods &= ~MOD_MASK_SHIFT;
            }
            return;
        default:
            break;
    }

    if (!pressed) {
        return;
    }

    const uint8_t mods = (get_mods() | get_oneshot_mods() | connection_hotkey_mods);
    const uint8_t required_mods = MOD_MASK_CTRL | MOD_MASK_ALT | MOD_MASK_SHIFT;

    if ((mods & required_mods) != required_mods) {
        return;
    }

    switch (keycode) {
        case KC_Q:
            connection_mode = CONNECTION_MODE_BLUETOOTH;
            break;
        case KC_W:
            connection_mode = CONNECTION_MODE_USB;
            break;
        case KC_E:
            connection_mode = CONNECTION_MODE_24G;
            break;
        default:
            return;
    }

    kb_storage.connection_mode = (uint8_t)connection_mode;
    eeconfig_update_user(kb_storage.raw);
}

static void set_trackpoint_enabled(bool enabled) {
    if (trackpoint_enabled == enabled) {
        return;
    }

    trackpoint_enabled = enabled;

#if defined(MOUSEKEY_ENABLE) && defined(PS2_MOUSE_ENABLE)
    if (!trackpoint_enabled) {
        extern int tp_buttons;

        tp_buttons = 0;
        mousekey_off((uint8_t)QK_MOUSE_BUTTON_1);
        mousekey_off((uint8_t)QK_MOUSE_BUTTON_2);
        mousekey_off((uint8_t)QK_MOUSE_BUTTON_3);
        mousekey_send();
    }
#endif
}

void eeconfig_init_user(void) {  // EEPROM is getting reset!
    kb_storage.raw = 0;
    kb_storage.flag_rgb_indicator = true;
    kb_storage.flag_rgb_sound     = true; // We want this enabled by default
    kb_storage.connection_mode    = CONNECTION_MODE_USB;
    eeconfig_update_user(kb_storage.raw); // Write default value to EEPROM now
}

void keyboard_post_init_user(void) {
    kb_storage.raw = eeconfig_read_user();

    if (kb_storage.connection_mode <= CONNECTION_MODE_24G) {
        connection_mode = (connection_mode_t)kb_storage.connection_mode;
    } else {
        connection_mode = CONNECTION_MODE_USB;
        kb_storage.connection_mode = CONNECTION_MODE_USB;
        eeconfig_update_user(kb_storage.raw);
    }

    gpio_set_pin_input_low(ENCODER_BUTTON_PIN);
    wireless_status_input_init(&wireless_power_red);
    wireless_status_input_init(&wireless_power_blue);
    encoder_led_effect_timer = timer_read32();
    encoder_led_fade_timer   = encoder_led_effect_timer;
    set_encoder_led_state(true);
    local_clock.last_tick = timer_read32();
    lock_time_sync.last_led_raw = host_keyboard_led_state().raw;

    oled_boot_timer     = timer_read32();
    last_keypress_timer = oled_boot_timer;
}

void matrix_scan_user(void) {
    const bool encoder_button_pressed = gpio_read_pin(ENCODER_BUTTON_PIN);

    wireless_status_input_task(&wireless_power_red);
    wireless_status_input_task(&wireless_power_blue);
    wireless_visible_color_task();
    local_clock_task();

    if (encoder_button_pressed != encoder_button_raw) {
        encoder_button_raw   = encoder_button_pressed;
        encoder_button_timer = timer_read();
    }

    if (timer_elapsed(encoder_button_timer) >= 5 && encoder_button_pressed != encoder_button_stable) {
        encoder_button_stable = encoder_button_pressed;

        if (encoder_button_stable) {
            encoder_is_muted = !encoder_is_muted;
            last_keypress_timer = timer_read32();
            encoder_led_note_activity();
            tap_code(KC_MUTE);
        }
    }

    encoder_led_task();
}

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    update_connection_mode_from_hotkey(keycode, record->event.pressed);

    if (record->event.pressed && IS_ENCODEREVENT(record->event)) {
        encoder_last_clockwise = (record->event.type == ENCODER_CW_EVENT);
        last_encoder_timer     = timer_read32();
        last_keypress_timer    = last_encoder_timer;
        encoder_led_note_activity();
    }

    if (record->event.pressed) {
        last_keypress_timer = timer_read32();
    }

#if defined(MOUSEKEY_ENABLE) && defined(PS2_MOUSE_ENABLE)
    if (keycode >= QK_MOUSE_BUTTON_1 && keycode <= QK_MOUSE_BUTTON_3) {
        extern int tp_buttons;

        if (!trackpoint_enabled) {
            return false;
        }

        if (record->event.pressed) {
            mousekey_on((uint8_t)keycode);
            tp_buttons |= MOUSE_BTN_MASK(keycode - QK_MOUSE_BUTTON_1);
        } else {
            mousekey_off((uint8_t)keycode);
            tp_buttons &= ~MOUSE_BTN_MASK(keycode - QK_MOUSE_BUTTON_1);
        }

        mousekey_send();
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
        case K_TPTOG:
            if (record->event.pressed) {
                set_trackpoint_enabled(!trackpoint_enabled);
            }
            return false;
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

bool encoder_update_user(uint8_t index, bool clockwise) {
    encoder_last_clockwise = clockwise;
    last_encoder_timer     = timer_read32();

    return true;
}

int last_volume = 0;

void via_custom_value_command_kb(uint8_t *data, uint8_t length) {
    // data = [ command_id, channel_id, value_id, value_data ]
    uint8_t *command_id = &(data[0]);

    if (*command_id != id_custom_set_value || length < 4) {
        *command_id = id_unhandled;
        return;
    }

    switch (data[2]) {
        case LOCAL_CLOCK_TIME_VALUE_ID: {
            const uint8_t seconds = length >= 6 ? data[5] : 0;

            if (length >= 5 && local_clock_set_time(data[3], data[4], seconds)) {
                return;
            }
            break;
        }
        case LOCAL_CLOCK_DATETIME_VALUE_ID:
            if (length >= 9 && local_clock_set_datetime((uint16_t)data[3] + 2000, data[4], data[5], data[6], data[7], data[8])) {
                return;
            }
            break;
        default:
            if (last_volume != data[3]) {
                encoder_led_note_activity();
            }

            last_volume = data[3];
            return;
    }

    *command_id = id_unhandled;
}

#ifdef PS2_MOUSE_ENABLE
static mouse_xy_report_t scale_trackpoint_axis(mouse_xy_report_t value) {
    int16_t scaled = ((int16_t)value * 60) / 100;

    if (scaled == 0 && value != 0) {
        return value > 0 ? 1 : -1;
    }

    return (mouse_xy_report_t)scaled;
}

void ps2_mouse_moved_user(report_mouse_t *mouse_report) {
    extern int tp_buttons;

    if (!trackpoint_enabled) {
        mouse_report->x = 0;
        mouse_report->y = 0;
        mouse_report->h = 0;
        mouse_report->v = 0;
        return;
    }

    mouse_report->buttons = tp_buttons;
    mouse_report->x = scale_trackpoint_axis(mouse_report->x);
    mouse_report->y = scale_trackpoint_axis(mouse_report->y);
    mouse_report->h = scale_trackpoint_axis(mouse_report->h);
    mouse_report->v = scale_trackpoint_axis(mouse_report->v);
}

void ps2_mouse_init_user(void) {
    ps2_mouse_set_resolution(PS2_MOUSE_4_COUNT_MM);
    ps2_mouse_set_sample_rate(PS2_MOUSE_100_SAMPLES_SEC);
}
#endif

#ifdef OLED_ENABLE
enum {
    OLED_TIME_DIGIT_0_X = 10,
    OLED_TIME_DIGIT_1_X = 16,
    OLED_TIME_DIGIT_2_X = 28,
    OLED_TIME_DIGIT_3_X = 34,
    OLED_TIME_Y         = 2,
    OLED_ENCODER_X      = 40,
    OLED_ENCODER_Y      = 2,
    OLED_CONNECTION_X   = 96,
    OLED_CONNECTION_Y   = 2,
    OLED_BATTERY_X      = 110,
    OLED_BATTERY_Y      = 4,
    OLED_TRACKPOINT_X   = 3,
    OLED_TRACKPOINT_Y   = 10,
    OLED_SOLENOID_X     = 20,
    OLED_SOLENOID_Y     = 12,
    OLED_KEY_X          = 44,
    OLED_KEY_Y          = 12,
    OLED_NUMLOCK_X      = 82,
    OLED_NUMLOCK_Y      = 10,
    OLED_CAPSLOCK_X     = 98,
    OLED_CAPSLOCK_Y     = 10,
    OLED_SCROLLLOCK_X   = 111,
    OLED_SCROLLLOCK_Y   = 10,
    OLED_RGB_X          = 2,
    OLED_RGB_Y          = 30,
    OLED_BUZZER_X       = 24,
    OLED_BUZZER_Y       = 29,
    OLED_LAYER_X        = 84,
    OLED_LAYER_Y        = 37,
    OLED_LABEL_X        = 2,
    OLED_LABEL_Y        = 51,
    OLED_VOLUME_BAR_X   = 16,
    OLED_VOLUME_BAR_Y   = 52,
};

#define OLED_SPLASH_DURATION_MS 2000
#define OLED_IDLE_SPLASH_MS    60000
#define OLED_ACTIVE_BRIGHTNESS  255
#define OLED_IDLE_BRIGHTNESS     32
#define OLED_KEY_ACTIVE_MS       180
#define OLED_ENCODER_ACTIVE_MS   300

static uint8_t oledbuffer[OLED_MATRIX_SIZE];

static const oled_bitmap_t *const oled_digits[] = {
    &oled_bitmap_digit_0,
    &oled_bitmap_digit_1,
    &oled_bitmap_digit_2,
    &oled_bitmap_digit_3,
    &oled_bitmap_digit_4,
    &oled_bitmap_digit_5,
    &oled_bitmap_digit_6,
    &oled_bitmap_digit_7,
    &oled_bitmap_digit_8,
    &oled_bitmap_digit_9,
};

static bool oled_bitmap_get_pixel(const oled_bitmap_t *bitmap, uint8_t x, uint8_t y) {
    const uint16_t bit_index  = ((uint16_t)y * bitmap->width) + x;
    const uint16_t byte_index = bit_index / 8;
    const uint8_t  bit_offset = 7 - (bit_index % 8);

    return (pgm_read_byte(bitmap->data + byte_index) & (1 << bit_offset)) != 0;
}

static void oled_set_pixel(uint8_t *frame, uint8_t x, uint8_t y) {
    if (x >= OLED_DISPLAY_WIDTH || y >= OLED_DISPLAY_HEIGHT) {
        return;
    }

    frame[(y / 8) * OLED_DISPLAY_WIDTH + x] |= (1 << (y & 7));
}

static void oled_draw_bitmap(uint8_t *frame, uint8_t x, uint8_t y, const oled_bitmap_t *bitmap) {
    for (uint8_t row = 0; row < bitmap->height; row++) {
        for (uint8_t col = 0; col < bitmap->width; col++) {
            if (oled_bitmap_get_pixel(bitmap, col, row)) {
                oled_set_pixel(frame, x + col, y + row);
            }
        }
    }
}

static void oled_draw_time(uint8_t *frame) {
    uint8_t hour_tens   = 0;
    uint8_t hour_ones   = 0;
    uint8_t minute_tens = 0;
    uint8_t minute_ones = 0;

    if (local_clock.valid) {
        hour_tens   = local_clock.hour / 10;
        hour_ones   = local_clock.hour % 10;
        minute_tens = local_clock.minute / 10;
        minute_ones = local_clock.minute % 10;
    }

    oled_draw_bitmap(frame, OLED_TIME_DIGIT_0_X, OLED_TIME_Y, oled_digits[hour_tens]);
    oled_draw_bitmap(frame, OLED_TIME_DIGIT_1_X, OLED_TIME_Y, oled_digits[hour_ones]);
    oled_draw_bitmap(frame, OLED_TIME_DIGIT_2_X, OLED_TIME_Y, oled_digits[minute_tens]);
    oled_draw_bitmap(frame, OLED_TIME_DIGIT_3_X, OLED_TIME_Y, oled_digits[minute_ones]);
}

static const oled_bitmap_t *oled_get_encoder_bitmap(void) {
    if (timer_elapsed32(last_encoder_timer) < OLED_ENCODER_ACTIVE_MS) {
        return encoder_last_clockwise ? &oled_bitmap_encoder_cw : &oled_bitmap_encoder_ccw;
    }

    return encoder_is_muted ? &oled_bitmap_encoder_mute : &oled_bitmap_encoder_idle;
}

static const oled_bitmap_t *oled_get_connection_bitmap(void) {
    switch (connection_mode) {
        case CONNECTION_MODE_BLUETOOTH:
            return &oled_bitmap_conn_bluetooth;
        case CONNECTION_MODE_24G:
            return &oled_bitmap_conn_wireless;
        case CONNECTION_MODE_USB:
        default:
            return &oled_bitmap_conn_usb;
    }
}

static const oled_bitmap_t *oled_get_rgb_bitmap(void) {
#ifdef RGB_MATRIX_ENABLE
    if (!rgb_matrix_is_enabled()) {
        return &oled_bitmap_rgb_off;
    }

    const uint8_t value = rgb_matrix_get_val();
    if (value < 85) {
        return &oled_bitmap_rgb_on_1;
    }
    if (value < 170) {
        return &oled_bitmap_rgb_on_2;
    }
    return &oled_bitmap_rgb_on_3;
#else
    return &oled_bitmap_rgb_off;
#endif
}

static const oled_bitmap_t *oled_get_buzzer_bitmap(void) {
#if defined(AUDIO_ENABLE) && defined(AUDIO_CLICKY)
    if (!is_audio_on() || !is_clicky_on()) {
        return &oled_bitmap_buzzer_off;
    }

    if (clicky_freq < 142.0f) {
        return &oled_bitmap_buzzer_on_1;
    }

    if (clicky_freq < 311.0f) {
        return &oled_bitmap_buzzer_on_2;
    }

    if (clicky_freq < 681.0f) {
        return &oled_bitmap_buzzer_on_3;
    }

    return &oled_bitmap_buzzer_on_4;
#elif defined(AUDIO_ENABLE)
    return is_audio_on() ? &oled_bitmap_buzzer_on_4 : &oled_bitmap_buzzer_off;
#else
    return &oled_bitmap_buzzer_off;
#endif
}

static const oled_bitmap_t *oled_get_solenoid_bitmap(void) {
#ifdef HAPTIC_ENABLE
    if (!haptic_get_enable()) {
        return &oled_bitmap_solenoid_off;
    }

    return haptic_config.buzz ? &oled_bitmap_solenoid_burst : &oled_bitmap_solenoid_single;
#else
    return &oled_bitmap_solenoid_off;
#endif
}

static const oled_bitmap_t *oled_get_key_bitmap(void) {
    return timer_elapsed32(last_keypress_timer) < OLED_KEY_ACTIVE_MS ? &oled_bitmap_key_active : &oled_bitmap_key_idle;
}

static const oled_bitmap_t *oled_get_lock_bitmap(bool enabled, const oled_bitmap_t *off_bitmap, const oled_bitmap_t *on_bitmap) {
    return enabled ? on_bitmap : off_bitmap;
}

static const oled_bitmap_t *oled_get_layer_bitmap(void) {
    switch (get_highest_layer(layer_state | default_layer_state)) {
        case 1:
            return &oled_bitmap_layer_1;
        case 2:
        default:
    return get_highest_layer(layer_state | default_layer_state) >= 2 ? &oled_bitmap_layer_2 : &oled_bitmap_layer_0;
    }
}

static const oled_bitmap_t *oled_get_battery_bitmap(void) {
    switch (wireless_get_charge_state()) {
        case WIRELESS_CHARGE_STATE_CHARGING:
            return &oled_bitmap_battery_charging;
        case WIRELESS_CHARGE_STATE_FULL:
            return &oled_bitmap_battery_4;
        case WIRELESS_CHARGE_STATE_LOW:
            return &oled_bitmap_battery_low;
        case WIRELESS_CHARGE_STATE_NORMAL:
        default:
            break;
    }

#ifdef BATTERY_ENABLE
    const uint8_t percent = battery_get_percent();

    if (percent <= 5 && wireless_get_charge_state() == WIRELESS_CHARGE_STATE_UNKNOWN) {
        return &oled_bitmap_battery_low;
    }
    if (percent < 20) {
        return wireless_get_charge_state() == WIRELESS_CHARGE_STATE_NORMAL ? &oled_bitmap_battery_1 : &oled_bitmap_battery_0;
    }
    if (percent < 40) {
        return &oled_bitmap_battery_1;
    }
    if (percent < 60) {
        return &oled_bitmap_battery_2;
    }
    if (percent < 80) {
        return &oled_bitmap_battery_3;
    }
    return &oled_bitmap_battery_4;
#else
    return &oled_bitmap_battery_4;
#endif
}

static uint8_t oled_get_volume_level(void) {
    if (encoder_is_muted || last_volume <= 0) {
        return 0;
    }

    if (last_volume <= 12) {
        return ((uint8_t)last_volume * 9 + 11) / 12;
    }

    return ((uint8_t)last_volume * 9 + 99) / 100;
}

static const oled_bitmap_t *oled_get_volume_bar_bitmap(void) {
    switch (oled_get_volume_level()) {
        case 1:
            return &oled_bitmap_volume_bar_1;
        case 2:
            return &oled_bitmap_volume_bar_2;
        case 3:
            return &oled_bitmap_volume_bar_3;
        case 4:
            return &oled_bitmap_volume_bar_4;
        case 5:
            return &oled_bitmap_volume_bar_5;
        case 6:
            return &oled_bitmap_volume_bar_6;
        case 7:
            return &oled_bitmap_volume_bar_7;
        case 8:
            return &oled_bitmap_volume_bar_8;
        case 9:
            return &oled_bitmap_volume_bar_9;
        default:
            return &oled_bitmap_volume_bar_empty;
    }
}

static const oled_bitmap_t *oled_get_volume_label_bitmap(void) {
    if (encoder_is_muted) {
        return &oled_bitmap_mute_label;
    }

    const uint8_t level = oled_get_volume_level();
    if (level >= 7) {
        return &oled_bitmap_volume_label_3;
    }
    if (level >= 4) {
        return &oled_bitmap_volume_label_2;
    }
    return &oled_bitmap_volume_label_1;
}

static void oled_render_dashboard(void) {
    const led_t led_state = host_keyboard_led_state();

    memset(oledbuffer, 0, sizeof(oledbuffer));
    oled_draw_bitmap(oledbuffer, 0, 0, &oled_bitmap_dashboard_base);
    oled_draw_time(oledbuffer);

    oled_draw_bitmap(oledbuffer, OLED_ENCODER_X, OLED_ENCODER_Y, oled_get_encoder_bitmap());
    oled_draw_bitmap(oledbuffer, OLED_CONNECTION_X, OLED_CONNECTION_Y, oled_get_connection_bitmap());
    oled_draw_bitmap(oledbuffer, OLED_BATTERY_X, OLED_BATTERY_Y, oled_get_battery_bitmap());
    oled_draw_bitmap(oledbuffer, OLED_TRACKPOINT_X, OLED_TRACKPOINT_Y, trackpoint_enabled ? &oled_bitmap_trackpoint_on : &oled_bitmap_trackpoint_off);
    oled_draw_bitmap(oledbuffer, OLED_SOLENOID_X, OLED_SOLENOID_Y, oled_get_solenoid_bitmap());
    oled_draw_bitmap(oledbuffer, OLED_KEY_X, OLED_KEY_Y, oled_get_key_bitmap());
    oled_draw_bitmap(oledbuffer, OLED_NUMLOCK_X, OLED_NUMLOCK_Y, oled_get_lock_bitmap(led_state.num_lock, &oled_bitmap_numlock_off, &oled_bitmap_numlock_on));
    oled_draw_bitmap(oledbuffer, OLED_CAPSLOCK_X, OLED_CAPSLOCK_Y, oled_get_lock_bitmap(led_state.caps_lock, &oled_bitmap_capslock_off, &oled_bitmap_capslock_on));
    oled_draw_bitmap(oledbuffer, OLED_SCROLLLOCK_X, OLED_SCROLLLOCK_Y, oled_get_lock_bitmap(led_state.scroll_lock, &oled_bitmap_scrolllock_off, &oled_bitmap_scrolllock_on));
    oled_draw_bitmap(oledbuffer, OLED_RGB_X, OLED_RGB_Y, oled_get_rgb_bitmap());
    oled_draw_bitmap(oledbuffer, OLED_BUZZER_X, OLED_BUZZER_Y, oled_get_buzzer_bitmap());
    oled_draw_bitmap(oledbuffer, OLED_LAYER_X, OLED_LAYER_Y, oled_get_layer_bitmap());
    oled_draw_bitmap(oledbuffer, OLED_LABEL_X, OLED_LABEL_Y, oled_get_volume_label_bitmap());
    oled_draw_bitmap(oledbuffer, OLED_VOLUME_BAR_X, OLED_VOLUME_BAR_Y, oled_get_volume_bar_bitmap());
}

oled_rotation_t oled_init_user(oled_rotation_t rotation) {
    return OLED_ROTATION_0;
}

bool oled_task_user(void) {
    const bool boot_splash_active = timer_elapsed32(oled_boot_timer) < OLED_SPLASH_DURATION_MS;
    const bool idle_splash_active = timer_elapsed32(last_keypress_timer) >= OLED_IDLE_SPLASH_MS;
    const bool show_splash        = boot_splash_active || idle_splash_active;
    const uint8_t target_brightness = (idle_splash_active && !boot_splash_active) ? OLED_IDLE_BRIGHTNESS : OLED_ACTIVE_BRIGHTNESS;

    if (oled_get_brightness() != target_brightness) {
        oled_set_brightness(target_brightness);
    }

    if (show_splash) {
        memset(oledbuffer, 0, sizeof(oledbuffer));
        oled_draw_bitmap(oledbuffer, 0, 0, &oled_bitmap_boot_splash);
    } else {
        oled_render_dashboard();
    }

    oled_set_cursor(0, 0);
    oled_write_raw((const char *)oledbuffer, sizeof(oledbuffer));

    return false;
}
#endif

bool led_update_user(led_t led_state) {
    lock_time_sync_handle_led_state(led_state);
    return true;
}


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
