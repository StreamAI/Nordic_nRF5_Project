:: Generate a bootloader settings hex file for an nRF52 device
nrfutil settings generate --family NRF52 ^
--application ble_app_buttonless_dfu_pca10040_s132.hex ^
--application-version-string "1.0.0" ^
--bootloader-version 1 ^
--bl-settings-version 2  ^
bl-settings.hex

:: Merge four HEX files into one hex file
 mergehex --merge bl-settings.hex ^
 secure_bootloader_ble_s132_pca10040.hex ^
 s132_nrf52_7.2.0_softdevice.hex ^
 ble_app_buttonless_dfu_pca10040_s132.hex ^
 --output all_ble_buttonless_dfu_nrf52832_s132.hex

:: Erase chip and program the merge file to an nRF52 SoC
nrfjprog --family NRF52 ^
--program all_ble_buttonless_dfu_nrf52832_s132.hex ^
--chiperase ^
--verify ^
--reset

pause