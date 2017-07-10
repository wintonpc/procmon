#!/usr/bin/env ruby

require 'fileutils'

class Procmon
  def initialize(pid)
    @pid = pid
    @period = 1
  end

  Stats = Struct.new(:virtual_memory_mb, :resident_set_mb, :total_cpu_seconds)

  def go
    write_gnuplot_script
    FileUtils.rm_f(log_path)
    run("eog #{cpu_png_path}", background: true)
    run("eog #{mem_png_path}", background: true)

    loop do
      a = measure
      sleep(@period)
      b = measure
      percent_cpu = ((b.total_cpu_seconds - a.total_cpu_seconds) / @period.to_f) * 100
      # puts "VMEM #{b.virtual_memory_mb.round(3)} MB  " +
      #          "RSS: #{b.resident_set_mb.round(3)} MB  " +
      #          "TOTAL CPU: #{b.total_cpu_seconds.round(3)} sec  " +
      #          "% CPU: #{percent_cpu.round}"
      File.open(log_path, 'a') do |f|
        f.write([
                    b.virtual_memory_mb.round(3),
                    b.resident_set_mb.round(3),
                    percent_cpu.round
                ].map(&:to_s).join(' ') + "\n")
      end
      run("gnuplot #{gnuplot_script_path}")
    end
  end

  def measure
    vs = File.read("/proc/#{@pid}/stat").strip.split(/\s+/)
    vs.unshift(nil) # make it "1-based" to align with http://man7.org/linux/man-pages/man5/proc.5.html
    user_mode_ticks = vs[14].to_i
    kernel_mode_ticks = vs[15].to_i
    s = Stats.new
    s.virtual_memory_mb = vs[23].to_i / (2 ** 20).to_f
    s.resident_set_mb = (vs[24].to_i * system_page_size) / (2 ** 20).to_f
    s.total_cpu_seconds = (user_mode_ticks + kernel_mode_ticks) / clock_hertz.to_f
    s
  end

  def run(cmd, background: false)
    (background ? spawn(cmd) : system(cmd)) or abort "FAILED: #{cmd}"
  end

  def path_prefix
    "/tmp/procmon-#{@pid}-"
  end

  def cpu_png_path
    path_of('cpu.png')
  end

  def mem_png_path
    path_of('mem.png')
  end

  def gnuplot_script_path
    path_of('gnuplot.script')
  end

  def log_path
    path_of('.log')
  end

  def system_page_size
    @system_page_size ||= `getconf PAGESIZE`.to_i
  end

  def clock_hertz
    @clock_hertz ||= Etc.sysconf(Etc::SC_CLK_TCK)
  end

  def path_of(suffix)
    path_prefix + suffix
  end

  def write_gnuplot_script
    File.write gnuplot_script_path, <<EOD
set term png small size 2556,600 background rgb 'gray10'
set output "#{mem_png_path}"

set border lc 'gray90'
set tics tc rgb 'gray90'
set key tc rgb 'gray90'

set ylabel "MB" tc rgb 'gray90'
set y2label "MB" tc rgb 'gray90'

set ytics nomirror
set y2tics nomirror in

set yrange [0:*]
set y2range [0:*]

plot "#{log_path}" using 1 with lines axes x1y1 title "Virtual", \
     "#{log_path}" using 2 with lines axes x1y1 title "Resident", \
     
     
set output "#{cpu_png_path}"

set ylabel "% CPU" tc rgb 'gray90'
set y2label "% CPU" tc rgb 'gray90'

set ytics nomirror

set yrange [0:*]

plot "#{log_path}" using 3 with lines axes x1y1 title "% CPU"
EOD
  end
end

pid = ARGV[0]
Procmon.new(pid).go
