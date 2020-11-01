import sensor, image, time, utime
from pyb import UART, LED

LOWER_THRESHOLD = 100
THRESHOLD = (0, LOWER_THRESHOLD)
led = LED(3)

sensor.reset()
sensor.set_pixformat(sensor.GRAYSCALE)
sensor.set_framesize(sensor.QQVGA)
sensor.skip_frames(time = 2000)

sensor.set_contrast(0)
sensor.set_brightness(0)
sensor.set_saturation(0)
sensor.set_auto_exposure(False, sensor.get_exposure_us())
sensor.set_auto_whitebal(False, sensor.get_rgb_gain_db())

SENSOR_WIDTH = sensor.width()
SENSOR_HEIGHT = sensor.height()

uart = UART(3)
uart.init(9600, bits=8, parity=None, stop=1, timeout_char=1000)
def uartSend(inputStr):
    uart.writechar(ord('{'))
    for iter in inputStr:
        uart.writechar(ord(iter))
    uart.writechar(ord('}'))

while(True):
    FLAG = b'e'
    if (uart.any() > 0):
        FLAG = uart.read(1)
    if (FLAG == b'c'):
        led.on()
        img = sensor.snapshot().binary([THRESHOLD])
        center_mass_x = 0
        center_mass_y = 0
        center_mass_weight = 0
        for blob in img.find_blobs([(255,255)], pixels_threshold=100, area_threshold=100, merge=True):
            center_mass_x += blob.cx()*blob.pixels()
            center_mass_y += blob.cy()*blob.pixels()
            center_mass_weight += blob.pixels()
        if (center_mass_weight != 0):
            center_mass_x /= center_mass_weight*SENSOR_WIDTH
            center_mass_y /= center_mass_weight*SENSOR_HEIGHT
            uartSend('{:.6f} {:.6f}'.format(center_mass_x, center_mass_y))
        else:
            uartSend('-9.9 -9.9')
        led.off()
