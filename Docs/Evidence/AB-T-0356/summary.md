
### baseline (n=7)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| cold_to_gpu_ready_s | 83.29 ms | 35.59 ms | 0.101 s | 22.29 ms |
| configure_s | 20.41 ms | 9.25 ms | 47.13 ms | 14.59 ms |
| gpu_touch2_rtt_s | 6.37 ms | 1.52 ms | 8.25 ms | 2.95 ms |
| gpu_touch_rtt_s | 16.34 ms | 11.85 ms | 21.91 ms | 3.29 ms |
| gpu_touch_worker_s | 13.88 ms | 11.20 ms | 16.49 ms | 1.97 ms |
| launch_to_hello_s | 38.90 ms | 13.90 ms | 57.48 ms | 15.31 ms |
| launch_to_main_s | 19.22 ms | 11.00 ms | 30.11 ms | 6.38 ms |
| main_to_hello_s | 18.28 ms | 2.86 ms | 27.37 ms | 9.08 ms |
| phys_after_configure | 5.3 MB | 5.2 MB | 5.5 MB | 0.1 MB |
| phys_after_configure_settled | 5.3 MB | 5.2 MB | 5.5 MB | 0.1 MB |
| phys_after_exit | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| phys_after_gpu | 146.1 MB | 145.4 MB | 146.6 MB | 0.4 MB |
| phys_after_gpu_settled | 146.1 MB | 145.4 MB | 146.6 MB | 0.4 MB |
| phys_after_hello | 3.2 MB | 3.1 MB | 3.3 MB | 0.1 MB |
| phys_after_hello_settled | 3.2 MB | 3.1 MB | 3.3 MB | 0.1 MB |
| phys_after_unload | 145.6 MB | 144.8 MB | 146.1 MB | 0.4 MB |
| pid_gone_after_exit | 1 | 1 | 1 | 0 |
| probe_prepare_s | 3.06 ms | 0.27 ms | 9.40 ms | 3.59 ms |
| shutdown_to_exit_s | 6.51 ms | 5.57 ms | 12.43 ms | 2.56 ms |
| sys_anon_after | 53,248.1 MB | 52,844.5 MB | 53,292.4 MB | 206.1 MB |
| sys_anon_before | 53,254.4 MB | 52,896.7 MB | 53,278.6 MB | 172.5 MB |
| unload_s | 1.00 ms | 0.13 ms | 6.25 ms | 2.24 ms |
| worker_report_gpu_active | 0.3 MB | 0.0 MB | 0.3 MB | 0.1 MB |
| worker_report_phys_after_gpu | 146.1 MB | 145.3 MB | 146.6 MB | 0.4 MB |

### baseline-first-launch (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| cold_to_gpu_ready_s | 0.256 s | 0.245 s | 0.297 s | 25.46 ms |
| configure_s | 11.53 ms | 10.62 ms | 24.13 ms | 7.04 ms |
| gpu_touch2_rtt_s | 1.54 ms | 1.36 ms | 2.33 ms | 0.38 ms |
| gpu_touch_rtt_s | 8.80 ms | 8.44 ms | 19.48 ms | 4.77 ms |
| gpu_touch_worker_s | 8.55 ms | 8.19 ms | 18.91 ms | 4.62 ms |
| launch_to_hello_s | 0.235 s | 0.225 s | 0.259 s | 14.45 ms |
| launch_to_main_s | 0.232 s | 0.222 s | 0.255 s | 13.82 ms |
| main_to_hello_s | 2.95 ms | 2.78 ms | 4.66 ms | 0.82 ms |
| phys_after_configure | 5.2 MB | 5.1 MB | 5.4 MB | 0.1 MB |
| phys_after_configure_settled | 5.2 MB | 5.1 MB | 5.4 MB | 0.1 MB |
| phys_after_exit | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| phys_after_gpu | 145.1 MB | 145.0 MB | 145.9 MB | 0.4 MB |
| phys_after_gpu_settled | 145.1 MB | 145.0 MB | 145.9 MB | 0.4 MB |
| phys_after_hello | 3.1 MB | 3.1 MB | 3.2 MB | 0.1 MB |
| phys_after_hello_settled | 3.1 MB | 3.1 MB | 3.2 MB | 0.1 MB |
| phys_after_unload | 145.1 MB | 144.5 MB | 145.6 MB | 0.4 MB |
| pid_gone_after_exit | 1 | 1 | 1 | 0 |
| probe_prepare_s | 0.48 ms | 0.28 ms | 1.93 ms | 0.69 ms |
| shutdown_to_exit_s | 2.73 ms | 2.41 ms | 6.05 ms | 1.53 ms |
| sys_anon_after | 52,114.9 MB | 51,579.7 MB | 53,323.0 MB | 676.7 MB |
| sys_anon_before | 51,824.3 MB | 51,579.7 MB | 52,632.9 MB | 433.2 MB |
| unload_s | 0.13 ms | 0.09 ms | 0.26 ms | 0.07 ms |
| worker_report_gpu_active | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_report_phys_after_gpu | 145.1 MB | 145.0 MB | 145.9 MB | 0.4 MB |

### zimage-worker (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| cold_total_s | 12.523 s | 12.498 s | 12.736 s | 98.70 ms |
| cold_total_with_host_read_s | 12.542 s | 12.521 s | 12.760 s | 0.100 s |
| configure_s | 8.58 ms | 7.57 ms | 10.74 ms | 1.16 ms |
| launch_to_hello_s | 13.46 ms | 11.34 ms | 15.80 ms | 1.91 ms |
| launch_to_main_s | 10.41 ms | 8.70 ms | 11.81 ms | 1.33 ms |
| main_to_hello_s | 2.88 ms | 2.57 ms | 5.38 ms | 1.16 ms |
| peak_phys_prepare | 14,235.3 MB | 14,234.2 MB | 14,241.9 MB | 3.2 MB |
| peak_phys_run1 | 22,443.6 MB | 21,977.5 MB | 22,579.6 MB | 276.2 MB |
| peak_phys_run2 | 22,580.7 MB | 22,516.1 MB | 22,897.3 MB | 151.3 MB |
| phys_after_configure | 5.2 MB | 5.2 MB | 5.3 MB | 0.0 MB |
| phys_after_hello | 3.2 MB | 3.1 MB | 3.2 MB | 0.0 MB |
| phys_after_prepare | 14,192.5 MB | 14,189.9 MB | 14,192.8 MB | 1.3 MB |
| phys_after_run1 | 14,293.4 MB | 14,252.4 MB | 14,295.1 MB | 18.5 MB |
| phys_after_run2 | 14,294.7 MB | 14,293.0 MB | 14,296.3 MB | 1.4 MB |
| phys_after_unload | 208.7 MB | 208.0 MB | 209.3 MB | 0.5 MB |
| prepare_s | 1.065 s | 1.025 s | 1.181 s | 61.36 ms |
| prepare_worker_s | 1.065 s | 1.025 s | 1.181 s | 61.42 ms |
| report_after_prepare.availableBytes | 24,100,000,000 | 24,100,000,000 | 24,100,000,000 | 0 |
| report_after_prepare.budgetBytes | 64,000,000,000 | 64,000,000,000 | 64,000,000,000 | 0 |
| report_after_prepare.date | 814,859,893.07 | 814,859,794.051 | 814,859,992.03 | 78.314 |
| report_after_prepare.gpuActiveBytes | 11,843,837,972 | 11,843,836,180 | 11,843,837,972 | 801.407 |
| report_after_prepare.gpuCacheBytes | 2,122,609,112 | 2,119,689,688 | 2,122,610,136 | 1,279,143.527 |
| report_after_prepare.physFootprintBytes | 14,192.5 MB | 14,189.9 MB | 14,192.8 MB | 1.3 MB |
| report_after_prepare.residentBytes | 11,900,000,000 | 11,900,000,000 | 11,900,000,000 | 0 |
| report_after_prepare.residents.z-image-turbo | 11,900,000,000 | 11,900,000,000 | 11,900,000,000 | 0 |
| report_after_prepare.transientReserveBytes | 28,000,000,000 | 28,000,000,000 | 28,000,000,000 | 0 |
| report_after_unload.availableBytes | 64,000,000,000 | 64,000,000,000 | 64,000,000,000 | 0 |
| report_after_unload.budgetBytes | 64,000,000,000 | 64,000,000,000 | 64,000,000,000 | 0 |
| report_after_unload.date | 814,859,916.255 | 814,859,817.01 | 814,860,015.053 | 78.326 |
| report_after_unload.gpuActiveBytes | 16 | 16 | 16 | 0 |
| report_after_unload.gpuCacheBytes | 0 | 0 | 0 | 0 |
| report_after_unload.physFootprintBytes | 2,416.2 MB | 2,357.0 MB | 2,420.5 MB | 33.4 MB |
| report_after_unload.residentBytes | 0 | 0 | 0 | 0 |
| report_after_unload.transientReserveBytes | 0 | 0 | 0 | 0 |
| run1_host_decode_s | 18.32 ms | 17.82 ms | 23.51 ms | 2.67 ms |
| run1_host_read_io_s | 0.21 ms | 0.16 ms | 0.29 ms | 0.05 ms |
| run1_output.bytes | 1.5 MB | 1.5 MB | 1.5 MB | 0.0 MB |
| run1_output.height | 1,024 | 1,024 | 1,024 | 0 |
| run1_output.width | 1,024 | 1,024 | 1,024 | 0 |
| run1_phase_first.decode | 9.942 s | 9.933 s | 9.973 s | 15.82 ms |
| run1_phase_first.denoise | 42.54 ms | 40.75 ms | 44.49 ms | 1.61 ms |
| run1_phase_first.encode | 0.53 ms | 0.41 ms | 0.61 ms | 0.07 ms |
| run1_phase_first.postprocess | 11.424 s | 11.370 s | 11.482 s | 42.97 ms |
| run1_progress_lines | 12 | 12 | 12 | 0 |
| run1_s | 11.466 s | 11.410 s | 11.529 s | 44.75 ms |
| run1_worker_s | 11.465 s | 11.410 s | 11.528 s | 44.56 ms |
| run2_host_decode_s | 15.10 ms | 14.12 ms | 20.09 ms | 2.82 ms |
| run2_host_read_io_s | 0.17 ms | 0.16 ms | 0.28 ms | 0.05 ms |
| run2_output.bytes | 1.5 MB | 1.5 MB | 1.5 MB | 0.0 MB |
| run2_output.height | 1,024 | 1,024 | 1,024 | 0 |
| run2_output.width | 1,024 | 1,024 | 1,024 | 0 |
| run2_phase_first.decode | 9.939 s | 9.917 s | 9.967 s | 23.60 ms |
| run2_phase_first.denoise | 42.61 ms | 39.45 ms | 44.50 ms | 2.01 ms |
| run2_phase_first.encode | 0.33 ms | 0.30 ms | 0.39 ms | 0.03 ms |
| run2_phase_first.postprocess | 11.451 s | 11.388 s | 11.469 s | 38.49 ms |
| run2_progress_lines | 12 | 12 | 12 | 0 |
| run2_s | 11.503 s | 11.428 s | 11.516 s | 41.97 ms |
| run2_worker_s | 11.502 s | 11.427 s | 11.515 s | 41.85 ms |
| shutdown_to_exit_s | 4.27 ms | 4.17 ms | 12.99 ms | 3.88 ms |
| unload_s | 89.92 ms | 83.81 ms | 96.05 ms | 5.21 ms |

### zimage-inproc (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| cold_total_s | 12.587 s | 12.425 s | 12.646 s | 87.05 ms |
| engine_init_s | 9.42 ms | 8.00 ms | 43.30 ms | 15.40 ms |
| evict_s | 83.77 ms | 77.96 ms | 87.87 ms | 4.11 ms |
| peak_phys_prepare | 14,234.9 MB | 14,232.8 MB | 14,252.7 MB | 8.2 MB |
| peak_phys_run1 | 22,570.7 MB | 22,496.5 MB | 22,580.7 MB | 34.6 MB |
| peak_phys_run2 | 22,570.8 MB | 22,358.2 MB | 22,586.6 MB | 119.6 MB |
| phys_after_engine | 4.7 MB | 4.6 MB | 4.9 MB | 0.1 MB |
| phys_after_evict | 209.0 MB | 207.9 MB | 209.6 MB | 0.8 MB |
| phys_after_prepare | 14,183.2 MB | 14,182.3 MB | 14,200.4 MB | 7.9 MB |
| phys_after_run1 | 14,283.8 MB | 14,244.1 MB | 14,286.6 MB | 18.2 MB |
| phys_after_run2 | 14,283.3 MB | 14,244.9 MB | 14,287.1 MB | 20.9 MB |
| phys_at_main | 2.3 MB | 2.3 MB | 2.3 MB | 0.0 MB |
| prepare_s | 1.083 s | 1.034 s | 1.105 s | 29.53 ms |
| register_s | 0.19 ms | 0.15 ms | 0.22 ms | 0.03 ms |
| run1_image.bytes | 1.5 MB | 1.5 MB | 1.5 MB | 0.0 MB |
| run1_image.height | 1,024 | 1,024 | 1,024 | 0 |
| run1_image.width | 1,024 | 1,024 | 1,024 | 0 |
| run1_phase_first.decode | 9.945 s | 9.911 s | 10.020 s | 40.79 ms |
| run1_phase_first.denoise | 42.04 ms | 41.43 ms | 45.42 ms | 1.86 ms |
| run1_phase_first.encode | 0.30 ms | 0.20 ms | 0.40 ms | 0.08 ms |
| run1_phase_first.postprocess | 11.454 s | 11.345 s | 11.481 s | 56.73 ms |
| run1_s | 11.497 s | 11.384 s | 11.524 s | 58.94 ms |
| run2_image.bytes | 1.5 MB | 1.5 MB | 1.5 MB | 0.0 MB |
| run2_image.height | 1,024 | 1,024 | 1,024 | 0 |
| run2_image.width | 1,024 | 1,024 | 1,024 | 0 |
| run2_phase_first.decode | 9.925 s | 9.908 s | 9.979 s | 28.15 ms |
| run2_phase_first.denoise | 42.77 ms | 38.79 ms | 44.26 ms | 2.23 ms |
| run2_phase_first.encode | 0.06 ms | 0.05 ms | 0.06 ms | 0.00 ms |
| run2_phase_first.postprocess | 11.423 s | 11.367 s | 11.495 s | 48.92 ms |
| run2_s | 11.465 s | 11.405 s | 11.539 s | 51.61 ms |

### spool-external · 4k-png (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 7.0 MB | 7.0 MB | 7.0 MB | 0.0 MB |
| cleanup_s | 0.59 ms | 0.55 ms | 0.60 ms | 0.02 ms |
| codec_total_s | 0.514 s | 0.512 s | 0.516 s | 1.43 ms |
| echo_gpp_overhead_s | 0.22 ms | 0.17 ms | 0.27 ms | 0.03 ms |
| echo_rtt_s | 0.260 s | 0.257 s | 0.261 s | 1.36 ms |
| file_path_total_s | 6.34 ms | 6.32 ms | 6.37 ms | 0.02 ms |
| gpp_noop_rtt_s | 0.33 ms | 0.26 ms | 0.34 ms | 0.04 ms |
| host_read_decode_s | 99.74 ms | 99.17 ms | 0.100 s | 0.48 ms |
| host_read_io_s | 0.40 ms | 0.33 ms | 0.44 ms | 0.05 ms |
| host_write_encode_s | 0.158 s | 0.157 s | 0.158 s | 0.32 ms |
| host_write_io_s | 2.69 ms | 2.64 ms | 2.75 ms | 0.04 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 6.9 MB | 6.9 MB | 6.9 MB | 0.0 MB |
| worker_read_decode_s | 0.100 s | 99.61 ms | 0.101 s | 0.41 ms |
| worker_read_io_s | 0.33 ms | 0.31 ms | 0.43 ms | 0.06 ms |
| worker_write_encode_s | 0.157 s | 0.154 s | 0.158 s | 1.48 ms |
| worker_write_io_s | 2.67 ms | 2.67 ms | 2.71 ms | 0.02 ms |

### spool-external · 4k-tiff16 (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 66.4 MB | 66.4 MB | 66.4 MB | 0.0 MB |
| cleanup_s | 0.95 ms | 0.92 ms | 1.42 ms | 0.22 ms |
| codec_total_s | 0.122 s | 0.119 s | 0.134 s | 5.77 ms |
| echo_gpp_overhead_s | 0.21 ms | 0.17 ms | 1.37 ms | 0.52 ms |
| echo_rtt_s | 80.08 ms | 78.83 ms | 83.22 ms | 1.99 ms |
| file_path_total_s | 41.06 ms | 40.65 ms | 42.92 ms | 1.00 ms |
| gpp_noop_rtt_s | 0.33 ms | 0.24 ms | 0.35 ms | 0.05 ms |
| host_read_decode_s | 46.17 ms | 44.09 ms | 56.53 ms | 5.15 ms |
| host_read_io_s | 3.20 ms | 3.00 ms | 3.33 ms | 0.12 ms |
| host_write_encode_s | 15.99 ms | 15.78 ms | 16.43 ms | 0.28 ms |
| host_write_io_s | 17.40 ms | 17.20 ms | 18.35 ms | 0.47 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 66.4 MB | 66.4 MB | 66.4 MB | 0.0 MB |
| worker_read_decode_s | 43.81 ms | 42.79 ms | 45.44 ms | 1.23 ms |
| worker_read_io_s | 2.92 ms | 2.62 ms | 3.32 ms | 0.26 ms |
| worker_write_encode_s | 16.00 ms | 15.88 ms | 16.07 ms | 0.09 ms |
| worker_write_io_s | 17.34 ms | 17.12 ms | 17.81 ms | 0.26 ms |

### spool-external · 1080p-raw-120 (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 995.3 MB | 995.3 MB | 995.3 MB | 0.0 MB |
| cleanup_s | 16.41 ms | 15.03 ms | 22.33 ms | 2.84 ms |
| codec_total_s | 0.02 ms | 0.02 ms | 0.02 ms | 0.00 ms |
| echo_gpp_overhead_s | 4.72 ms | 3.88 ms | 7.03 ms | 1.58 ms |
| echo_rtt_s | 0.408 s | 0.396 s | 0.418 s | 10.37 ms |
| file_path_total_s | 0.799 s | 0.792 s | 0.832 s | 16.51 ms |
| gpp_noop_rtt_s | 5.25 ms | 2.83 ms | 12.53 ms | 4.02 ms |
| host_read_decode_s | 0.01 ms | 0.01 ms | 0.01 ms | 0.00 ms |
| host_read_io_s | 58.94 ms | 51.73 ms | 63.42 ms | 4.63 ms |
| host_write_encode_s | 0.00 ms | 0.00 ms | 0.00 ms | 0.00 ms |
| host_write_io_s | 0.334 s | 0.331 s | 0.364 s | 13.61 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 995.3 MB | 995.3 MB | 995.3 MB | 0.0 MB |
| worker_read_decode_s | 0.00 ms | 0.00 ms | 0.00 ms | 0.00 ms |
| worker_read_io_s | 62.61 ms | 55.73 ms | 70.21 ms | 6.37 ms |
| worker_write_encode_s | 0.01 ms | 0.01 ms | 0.01 ms | 0.00 ms |
| worker_write_io_s | 0.334 s | 0.333 s | 0.348 s | 6.65 ms |

### spool-external · 1080p-raw-600 (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 4,976.6 MB | 4,976.6 MB | 4,976.6 MB | 0.0 MB |
| cleanup_s | 0.439 s | 0.136 s | 0.504 s | 0.156 s |
| codec_total_s | 0.08 ms | 0.07 ms | 0.08 ms | 0.00 ms |
| echo_gpp_overhead_s | 33.55 ms | 29.98 ms | 38.74 ms | 3.99 ms |
| echo_rtt_s | 2.142 s | 2.081 s | 2.559 s | 0.196 s |
| file_path_total_s | 4.266 s | 4.158 s | 4.634 s | 0.194 s |
| gpp_noop_rtt_s | 3.48 ms | 3.22 ms | 4.18 ms | 0.40 ms |
| host_read_decode_s | 0.03 ms | 0.03 ms | 0.04 ms | 0.00 ms |
| host_read_io_s | 0.311 s | 0.298 s | 0.314 s | 6.62 ms |
| host_write_encode_s | 0.01 ms | 0.01 ms | 0.01 ms | 0.00 ms |
| host_write_io_s | 1.763 s | 1.728 s | 1.842 s | 44.24 ms |
| result_line_bytes | 0.1 MB | 0.1 MB | 0.1 MB | 0.0 MB |
| worker_bytes_out | 4,976.6 MB | 4,976.6 MB | 4,976.6 MB | 0.0 MB |
| worker_read_decode_s | 0.01 ms | 0.01 ms | 0.01 ms | 0.00 ms |
| worker_read_io_s | 0.333 s | 0.313 s | 0.339 s | 12.28 ms |
| worker_write_encode_s | 0.02 ms | 0.02 ms | 0.02 ms | 0.00 ms |
| worker_write_io_s | 1.798 s | 1.729 s | 2.183 s | 0.186 s |

### spool-external · 1080p-png-120 (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 313.7 MB | 313.7 MB | 313.7 MB | 0.0 MB |
| cleanup_s | 15.06 ms | 12.86 ms | 16.43 ms | 1.63 ms |
| codec_total_s | 22.676 s | 22.571 s | 22.703 s | 51.16 ms |
| echo_gpp_overhead_s | 7.59 ms | 6.80 ms | 8.68 ms | 0.76 ms |
| echo_rtt_s | 11.472 s | 11.370 s | 11.492 s | 50.45 ms |
| file_path_total_s | 0.297 s | 0.279 s | 0.339 s | 22.68 ms |
| gpp_noop_rtt_s | 2.84 ms | 1.52 ms | 5.17 ms | 1.39 ms |
| host_read_decode_s | 3.945 s | 3.916 s | 4.000 s | 36.37 ms |
| host_read_io_s | 20.17 ms | 19.16 ms | 22.07 ms | 1.31 ms |
| host_write_encode_s | 7.418 s | 7.369 s | 7.439 s | 27.27 ms |
| host_write_io_s | 0.119 s | 0.113 s | 0.141 s | 13.34 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 311.1 MB | 311.1 MB | 311.1 MB | 0.0 MB |
| worker_read_decode_s | 3.990 s | 3.923 s | 4.010 s | 39.46 ms |
| worker_read_io_s | 28.96 ms | 22.89 ms | 29.47 ms | 2.84 ms |
| worker_write_encode_s | 7.330 s | 7.301 s | 7.336 s | 15.63 ms |
| worker_write_io_s | 0.116 s | 0.113 s | 0.138 s | 10.44 ms |

### spool-external · 1080p-png-120-par (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 313.7 MB | 313.7 MB | 313.7 MB | 0.0 MB |
| cleanup_s | 13.69 ms | 12.78 ms | 14.00 ms | 0.54 ms |
| codec_total_s | 2.301 s | 2.248 s | 2.306 s | 24.88 ms |
| echo_gpp_overhead_s | 9.33 ms | 6.31 ms | 9.66 ms | 1.63 ms |
| echo_rtt_s | 1.229 s | 1.216 s | 1.301 s | 34.66 ms |
| file_path_total_s | 0.185 s | 0.175 s | 0.212 s | 14.05 ms |
| gpp_noop_rtt_s | 0.81 ms | 0.80 ms | 2.48 ms | 0.73 ms |
| host_read_decode_s | 0.346 s | 0.328 s | 0.387 s | 27.29 ms |
| host_read_io_s | 5.43 ms | 4.54 ms | 8.91 ms | 2.23 ms |
| host_write_encode_s | 0.786 s | 0.778 s | 0.801 s | 8.52 ms |
| host_write_io_s | 81.65 ms | 79.17 ms | 89.73 ms | 4.98 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 311.1 MB | 311.1 MB | 311.1 MB | 0.0 MB |
| worker_read_decode_s | 0.342 s | 0.338 s | 0.382 s | 18.70 ms |
| worker_read_io_s | 5.57 ms | 5.31 ms | 9.52 ms | 1.81 ms |
| worker_write_encode_s | 0.796 s | 0.786 s | 0.801 s | 6.93 ms |
| worker_write_io_s | 78.66 ms | 77.95 ms | 99.33 ms | 9.28 ms |

### spool-external · 1080p-png-600-par (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 1,568.3 MB | 1,568.3 MB | 1,568.3 MB | 0.0 MB |
| cleanup_s | 48.46 ms | 43.95 ms | 70.53 ms | 11.59 ms |
| codec_total_s | 12.129 s | 12.109 s | 12.146 s | 14.63 ms |
| echo_gpp_overhead_s | 54.04 ms | 41.88 ms | 56.69 ms | 6.23 ms |
| echo_rtt_s | 6.764 s | 6.617 s | 6.844 s | 92.46 ms |
| file_path_total_s | 1.259 s | 1.100 s | 1.371 s | 0.104 s |
| gpp_noop_rtt_s | 3.61 ms | 3.16 ms | 5.50 ms | 1.09 ms |
| host_read_decode_s | 2.160 s | 2.063 s | 2.165 s | 48.38 ms |
| host_read_io_s | 22.00 ms | 21.54 ms | 40.39 ms | 8.08 ms |
| host_write_encode_s | 3.922 s | 3.899 s | 3.932 s | 12.60 ms |
| host_write_io_s | 0.498 s | 0.472 s | 0.784 s | 0.131 s |
| result_line_bytes | 0.1 MB | 0.1 MB | 0.1 MB | 0.0 MB |
| worker_bytes_out | 1,555.7 MB | 1,555.7 MB | 1,555.7 MB | 0.0 MB |
| worker_read_decode_s | 2.183 s | 2.111 s | 2.236 s | 49.92 ms |
| worker_read_io_s | 36.06 ms | 22.57 ms | 39.39 ms | 7.20 ms |
| worker_write_encode_s | 3.902 s | 3.880 s | 3.917 s | 13.63 ms |
| worker_write_io_s | 0.612 s | 0.440 s | 0.686 s | 0.109 s |

### spool-internal · 4k-png (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 7.0 MB | 7.0 MB | 7.0 MB | 0.0 MB |
| cleanup_s | 0.61 ms | 0.58 ms | 0.64 ms | 0.02 ms |
| codec_total_s | 0.505 s | 0.503 s | 0.506 s | 1.10 ms |
| echo_gpp_overhead_s | 0.22 ms | 0.21 ms | 0.22 ms | 0.01 ms |
| echo_rtt_s | 0.253 s | 0.252 s | 0.254 s | 0.75 ms |
| file_path_total_s | 8.05 ms | 3.07 ms | 8.29 ms | 2.61 ms |
| gpp_noop_rtt_s | 0.27 ms | 0.25 ms | 0.28 ms | 0.01 ms |
| host_read_decode_s | 98.41 ms | 97.74 ms | 98.53 ms | 0.34 ms |
| host_read_io_s | 0.32 ms | 0.31 ms | 0.33 ms | 0.00 ms |
| host_write_encode_s | 0.156 s | 0.155 s | 0.156 s | 0.45 ms |
| host_write_io_s | 5.74 ms | 1.09 ms | 5.91 ms | 2.51 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 6.9 MB | 6.9 MB | 6.9 MB | 0.0 MB |
| worker_read_decode_s | 98.41 ms | 97.88 ms | 98.57 ms | 0.29 ms |
| worker_read_io_s | 0.32 ms | 0.31 ms | 0.32 ms | 0.00 ms |
| worker_write_encode_s | 0.152 s | 0.152 s | 0.153 s | 0.49 ms |
| worker_write_io_s | 1.46 ms | 1.13 ms | 1.51 ms | 0.16 ms |

### spool-internal · 4k-tiff16 (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 66.4 MB | 66.4 MB | 66.4 MB | 0.0 MB |
| cleanup_s | 1.46 ms | 1.42 ms | 1.52 ms | 0.04 ms |
| codec_total_s | 0.118 s | 0.118 s | 0.120 s | 1.09 ms |
| echo_gpp_overhead_s | 0.22 ms | 0.20 ms | 0.25 ms | 0.02 ms |
| echo_rtt_s | 67.62 ms | 67.49 ms | 72.08 ms | 1.97 ms |
| file_path_total_s | 17.05 ms | 16.18 ms | 23.67 ms | 3.27 ms |
| gpp_noop_rtt_s | 0.29 ms | 0.25 ms | 0.29 ms | 0.02 ms |
| host_read_decode_s | 43.35 ms | 43.23 ms | 44.31 ms | 0.45 ms |
| host_read_io_s | 3.14 ms | 3.11 ms | 3.20 ms | 0.04 ms |
| host_write_encode_s | 15.68 ms | 15.60 ms | 16.06 ms | 0.19 ms |
| host_write_io_s | 5.29 ms | 4.74 ms | 9.32 ms | 1.99 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 66.4 MB | 66.4 MB | 66.4 MB | 0.0 MB |
| worker_read_decode_s | 43.27 ms | 43.17 ms | 44.21 ms | 0.43 ms |
| worker_read_io_s | 3.08 ms | 2.98 ms | 3.14 ms | 0.06 ms |
| worker_write_encode_s | 15.70 ms | 15.61 ms | 15.92 ms | 0.14 ms |
| worker_write_io_s | 5.26 ms | 4.93 ms | 9.65 ms | 2.01 ms |

### spool-internal · 1080p-raw-120 (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 995.3 MB | 995.3 MB | 995.3 MB | 0.0 MB |
| cleanup_s | 32.75 ms | 32.19 ms | 43.70 ms | 4.87 ms |
| codec_total_s | 0.02 ms | 0.02 ms | 0.02 ms | 0.00 ms |
| echo_gpp_overhead_s | 4.22 ms | 3.80 ms | 4.94 ms | 0.50 ms |
| echo_rtt_s | 0.191 s | 0.189 s | 0.284 s | 41.82 ms |
| file_path_total_s | 0.377 s | 0.373 s | 0.468 s | 41.45 ms |
| gpp_noop_rtt_s | 0.89 ms | 0.89 ms | 0.92 ms | 0.01 ms |
| host_read_decode_s | 0.01 ms | 0.01 ms | 0.01 ms | 0.00 ms |
| host_read_io_s | 51.11 ms | 50.73 ms | 52.43 ms | 0.69 ms |
| host_write_encode_s | 0.00 ms | 0.00 ms | 0.00 ms | 0.00 ms |
| host_write_io_s | 0.134 s | 0.133 s | 0.135 s | 0.69 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 995.3 MB | 995.3 MB | 995.3 MB | 0.0 MB |
| worker_read_decode_s | 0.00 ms | 0.00 ms | 0.00 ms | 0.00 ms |
| worker_read_io_s | 58.90 ms | 58.49 ms | 60.91 ms | 1.07 ms |
| worker_write_encode_s | 0.01 ms | 0.01 ms | 0.01 ms | 0.00 ms |
| worker_write_io_s | 0.127 s | 0.127 s | 0.220 s | 41.51 ms |

### spool-internal · 1080p-raw-600 (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 4,976.6 MB | 4,976.6 MB | 4,976.6 MB | 0.0 MB |
| cleanup_s | 0.158 s | 0.152 s | 0.159 s | 3.63 ms |
| codec_total_s | 0.07 ms | 0.07 ms | 0.08 ms | 0.00 ms |
| echo_gpp_overhead_s | 28.21 ms | 27.18 ms | 30.01 ms | 1.02 ms |
| echo_rtt_s | 0.992 s | 0.983 s | 1.013 s | 10.95 ms |
| file_path_total_s | 1.949 s | 1.938 s | 1.980 s | 17.54 ms |
| gpp_noop_rtt_s | 3.36 ms | 3.24 ms | 3.49 ms | 0.09 ms |
| host_read_decode_s | 0.03 ms | 0.03 ms | 0.03 ms | 0.00 ms |
| host_read_io_s | 0.305 s | 0.301 s | 0.317 s | 6.17 ms |
| host_write_encode_s | 0.01 ms | 0.01 ms | 0.01 ms | 0.00 ms |
| host_write_io_s | 0.651 s | 0.650 s | 0.671 s | 8.89 ms |
| result_line_bytes | 0.1 MB | 0.1 MB | 0.1 MB | 0.0 MB |
| worker_bytes_out | 4,976.6 MB | 4,976.6 MB | 4,976.6 MB | 0.0 MB |
| worker_read_decode_s | 0.01 ms | 0.01 ms | 0.01 ms | 0.00 ms |
| worker_read_io_s | 0.320 s | 0.318 s | 0.328 s | 3.75 ms |
| worker_write_encode_s | 0.02 ms | 0.02 ms | 0.02 ms | 0.00 ms |
| worker_write_io_s | 0.644 s | 0.637 s | 0.662 s | 9.25 ms |

### spool-internal · 1080p-png-120 (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 313.7 MB | 313.7 MB | 313.7 MB | 0.0 MB |
| cleanup_s | 11.66 ms | 11.46 ms | 12.48 ms | 0.41 ms |
| codec_total_s | 19.223 s | 19.209 s | 19.463 s | 0.110 s |
| echo_gpp_overhead_s | 7.38 ms | 7.11 ms | 7.47 ms | 0.14 ms |
| echo_rtt_s | 9.653 s | 9.644 s | 9.878 s | 0.101 s |
| file_path_total_s | 0.148 s | 0.143 s | 0.154 s | 4.39 ms |
| gpp_noop_rtt_s | 0.94 ms | 0.93 ms | 1.00 ms | 0.03 ms |
| host_read_decode_s | 3.310 s | 3.307 s | 3.332 s | 10.40 ms |
| host_read_io_s | 17.99 ms | 17.79 ms | 19.14 ms | 0.54 ms |
| host_write_encode_s | 6.334 s | 6.333 s | 6.339 s | 2.55 ms |
| host_write_io_s | 48.33 ms | 47.78 ms | 55.95 ms | 4.05 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 311.1 MB | 311.1 MB | 311.1 MB | 0.0 MB |
| worker_read_decode_s | 3.327 s | 3.320 s | 3.336 s | 5.97 ms |
| worker_read_io_s | 25.73 ms | 24.84 ms | 26.45 ms | 0.58 ms |
| worker_write_encode_s | 6.248 s | 6.243 s | 6.470 s | 0.100 s |
| worker_write_io_s | 47.02 ms | 45.11 ms | 48.23 ms | 1.24 ms |

### spool-internal · 1080p-png-120-par (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 313.7 MB | 313.7 MB | 313.7 MB | 0.0 MB |
| cleanup_s | 15.20 ms | 14.09 ms | 23.44 ms | 3.91 ms |
| codec_total_s | 2.271 s | 2.092 s | 2.344 s | 94.35 ms |
| echo_gpp_overhead_s | 7.49 ms | 7.33 ms | 7.67 ms | 0.14 ms |
| echo_rtt_s | 1.183 s | 1.161 s | 1.199 s | 14.01 ms |
| file_path_total_s | 51.22 ms | 50.32 ms | 55.41 ms | 2.09 ms |
| gpp_noop_rtt_s | 1.16 ms | 1.10 ms | 1.80 ms | 0.30 ms |
| host_read_decode_s | 0.354 s | 0.348 s | 0.387 s | 16.18 ms |
| host_read_io_s | 4.56 ms | 4.50 ms | 8.62 ms | 1.78 ms |
| host_write_encode_s | 0.782 s | 0.574 s | 0.804 s | 95.22 ms |
| host_write_io_s | 16.50 ms | 16.36 ms | 16.62 ms | 0.11 ms |
| result_line_bytes | 0.0 MB | 0.0 MB | 0.0 MB | 0.0 MB |
| worker_bytes_out | 311.1 MB | 311.1 MB | 311.1 MB | 0.0 MB |
| worker_read_decode_s | 0.353 s | 0.343 s | 0.365 s | 8.12 ms |
| worker_read_io_s | 5.62 ms | 5.26 ms | 6.28 ms | 0.43 ms |
| worker_write_encode_s | 0.801 s | 0.788 s | 0.804 s | 8.10 ms |
| worker_write_io_s | 16.71 ms | 16.50 ms | 16.78 ms | 0.12 ms |

### spool-internal · 1080p-png-600-par (n=5)

| metric | median | min | max | stdev |
|---|---:|---:|---:|---:|
| bytes_in | 1,568.3 MB | 1,568.3 MB | 1,568.3 MB | 0.0 MB |
| cleanup_s | 68.36 ms | 66.12 ms | 71.28 ms | 1.92 ms |
| codec_total_s | 12.012 s | 11.991 s | 12.302 s | 0.130 s |
| echo_gpp_overhead_s | 44.24 ms | 43.16 ms | 54.71 ms | 4.77 ms |
| echo_rtt_s | 6.204 s | 6.194 s | 6.279 s | 35.38 ms |
| file_path_total_s | 0.316 s | 0.311 s | 0.357 s | 19.18 ms |
| gpp_noop_rtt_s | 4.21 ms | 4.09 ms | 4.24 ms | 0.06 ms |
| host_read_decode_s | 2.090 s | 2.072 s | 2.261 s | 78.38 ms |
| host_read_io_s | 22.91 ms | 21.51 ms | 24.59 ms | 1.12 ms |
| host_write_encode_s | 3.913 s | 3.904 s | 3.940 s | 14.39 ms |
| host_write_io_s | 0.111 s | 0.110 s | 0.113 s | 1.21 ms |
| result_line_bytes | 0.1 MB | 0.1 MB | 0.1 MB | 0.0 MB |
| worker_bytes_out | 1,555.7 MB | 1,555.7 MB | 1,555.7 MB | 0.0 MB |
| worker_read_decode_s | 2.109 s | 2.098 s | 2.133 s | 14.00 ms |
| worker_read_io_s | 23.39 ms | 23.03 ms | 23.82 ms | 0.28 ms |
| worker_write_encode_s | 3.909 s | 3.898 s | 3.969 s | 28.75 ms |
| worker_write_io_s | 0.115 s | 0.110 s | 0.157 s | 19.66 ms |
