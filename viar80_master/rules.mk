# MCU name
MCU = STM32F103

# Bootloader selection
BOOTLOADER = stm32duino

# Build Options
#   change yes to no to disable

MOUSEKEY_ENABLE = yes      # Mouse keys
EXTRAKEY_ENABLE = yes      # Audio control and System control
CONSOLE_ENABLE = no        # Console for debug
BACKLIGHT_ENABLE = no      # Enable keyboard backlight functionality
COMMAND_ENABLE = yes       # Commands for debug and configuration
BOOTMAGIC_ENABLE = yes     # Enable Bootmagic Lite
NKRO_ENABLE = yes          # Enable N-Key Rollover

RGBLIGHT_ENABLE = no
RGB_MATRIX_ENABLE= yes
RGB_MATRIX_DRIVER = ws2812
WS2812_DRIVER = bitbang
HAPTIC_ENABLE = yes
HAPTIC_DRIVER = solenoid
AUDIO_ENABLE = yes
AUDIO_DRIVER = pwm_hardware

SPLIT_KEYBOARD = yes
SERIAL_DRIVER = usart

RAW_ENABLE = no
OLED_ENABLE = yes
OLED_DRIVER = ssd1306
MOUSE_ENABLE = no
BATTERY_ENABLE = yes
BATTERY_DRIVER = adc

PS2_MOUSE_ENABLE = yes
PS2_ENABLE = yes
PS2_DRIVER = interrupt
#PROTOCOL_CHIBIOS = yes
# PS2_DRIVER = busywait

ENCODER_ENABLE = yes
ENCODER_MAP_ENABLE = yes
