# FPGA_WAV_Player

Простой проект, позволяющий воспроизводить wav файлы на FPGA или даже CPLD. В качестве носителя информации используется spi flash 25-й серии, на которую записывается wav файл формата PCM, 8-bit, U8, mono (можно сконвертировать с помощью online конвертера).  Частота дискретизации любая, при которой файл поместится на флешку. Для настройки необходимой частоты в проекте есть параметр "wav_freq".
