:: Generate a dfu package from the application file
nrfutil pkg generate ^
--application ble_app_uart_pca10040_s132_v111.hex ^
--application-version-string "1.1.1" ^
--hw-version 52 ^
--sd-req 0X0101 ^
--key-file private.pem ^
SDK1702_app_nus_dfu_s132_v111.zip

:: Display the contents of the created dfu package
nrfutil pkg display SDK1702_app_nus_dfu_s132_v111.zip

pause