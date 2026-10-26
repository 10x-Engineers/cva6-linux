################################################################################
#
# arty-led-cgi
#
################################################################################

ARTY_LED_CGI_VERSION = 1.0
ARTY_LED_CGI_SITE = $(BR2_EXTERNAL_ARTY_PATH)/package/arty-led-cgi/src
ARTY_LED_CGI_SITE_METHOD = local

define ARTY_LED_CGI_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -Wall -o $(@D)/led $(@D)/led.c
endef

define ARTY_LED_CGI_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/led $(TARGET_DIR)/srv/www/cgi-bin/led
endef

$(eval $(generic-package))
