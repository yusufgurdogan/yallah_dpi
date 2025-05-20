# YallahDPI Kurulum Rehberi

Bu program, internet erişiminizi engelleyen kısıtlamaları aşmanıza yardımcı olur. Kolay bir şekilde kurabilir ve kullanabilirsiniz.

## Hızlı Kurulum

### Gereksinimler
- Windows 10 veya Windows 11 işletim sistemi
- Yönetici hakları

### Kurulum Adımları

1. **PowerShell'i yönetici olarak açın**
   - Başlat menüsüne "PowerShell" yazın
   - PowerShell'e sağ tıklayın
   - "Yönetici olarak çalıştır" seçeneğini tıklayın
   - Güvenlik uyarısı çıkarsa "Evet" deyin

2. **Aşağıdaki komutu yapıştırın ve Enter tuşuna basın**

```
iwr -useb https://raw.githubusercontent.com/yusufgurdogan/yallah_dpi/main/quick-install.ps1 | iex
```

3. **Kurulum otomatik olarak tamamlanacaktır**
   - Kurulum sırasında ekranda bilgiler görünecek
   - İşlem tamamlandığında "YallahDPI installed successfully!" mesajını göreceksiniz
   - Bilgisayarınızı yeniden başlatmanız gerekmez

## Kontrol ve Kullanım

- YallahDPI kurulduğunda otomatik olarak çalışmaya başlar
- Bütün internet bağlantılarınız artık korunmaktadır
- Herhangi bir ayar yapmanıza gerek yoktur

## Durumu Kontrol Etme

PowerShell'de şu komutu yazabilirsiniz:
```
Get-Service YallahDPIGo
```

## Sorun Giderme

Eğer internet bağlantınızda sorun yaşarsanız:

1. PowerShell'i yönetici olarak açın
2. Aşağıdaki komutu yazın:
```
& "C:\Program Files\YallahDPI\check-status.ps1"
```
3. Servisin çalışıp çalışmadığını kontrol edin

## Kaldırma

YallahDPI'ı kaldırmak isterseniz:

1. PowerShell'i yönetici olarak açın
2. Aşağıdaki komutu yazın:
```
& "C:\Program Files\YallahDPI\uninstall-yallahdpi.ps1"
```
3. Kaldırma işlemi otomatik olarak gerçekleşecektir