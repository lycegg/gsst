./gpu_tehua /home/lycegg/wsl_codes/encoded/genome /home/lycegg/wsl_codes/encoded/genome_gpu_tehua
./a.out /home/lycegg/wsl_codes/encoded/genome_gpu_tehua /home/lycegg/wsl_codes/encoded/genome_gpu_jiema
diff /home/lycegg/wsl_codes/encoded/genome_gpu_jiema /home/lycegg/wsl_codes/fsst-master/paper/dbtext/genome

/home/lycegg/wsl_codes/fsst-master/build/fsst /home/lycegg/wsl_codes/lyc_tst/1664M /home/lycegg/wsl_codes/lyc_tst/1664M_cpu
./gpu_tehua /home/lycegg/wsl_codes/lyc_tst/1664M_cpu /home/lycegg/wsl_codes/encoded/1664M_tehua 128 0 >lyctemp
./a.out /home/lycegg/wsl_codes/encoded/1664M_tehua /home/lycegg/wsl_codes/encoded/1664M_gpu_jiema 30 0
diff /home/lycegg/wsl_codes/encoded/1664M_gpu_jiema /home/lycegg/wsl_codes/lyc_tst/1664M



/home/lycegg/wsl_codes/fsst-master/build/fsst /home/lycegg/wsl_codes/lyc_tst/1664M /home/lycegg/wsl_codes/lyc_tst/1664M_cpu
./gpu_marker /home/lycegg/wsl_codes/lyc_tst/1664M_cpu /home/lycegg/wsl_codes/encoded/1664M_tehua 128 0 >lyctemp
./a.out /home/lycegg/wsl_codes/encoded/1664M_tehua /home/lycegg/wsl_codes/encoded/1664M_gpu_jiema 0 1 128
diff /home/lycegg/wsl_codes/encoded/1664M_gpu_jiema /home/lycegg/wsl_codes/lyc_tst/1664M