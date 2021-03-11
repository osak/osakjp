require 'tempfile'
require 'fileutils'

def sed_i(filename, &block)
    File.open(filename) do |f|
        of = Tempfile.new('memoyoushi')
        changed = false
        f.each_line do |line|
            new_line = block.call(line)
            of.puts new_line
            if line != new_line
                changed = true
            end
        end
        of.close
        if changed
            FileUtils.move(of.path, filename)
        end
    end
end

dirs = %w(diary trip program other hardware linux food)

dirs.each do |dir|
    Dir.glob("memoyoushi-archive/#{dir}/**/*.html") do |path|
        puts path
        sed_i(path) { |line|
            if line.match(/<script src=/)
                ""
            else
                line.gsub(/(<link.*)style.css(")/) { "#{$1}style_memoyoushi.css#{$2}" }
                    .gsub(%r{(<a.*href=".*)index.html(".*>メモ用紙2.0</a>)}) { "#{$1}index_memoyoushi.html#{$2}" }
                    .gsub(%r{(class="kogarasi-mark".*>)(</div>)}) { "#{$1}ここにはかつてコメントが表示されていました#{$2}" }
            end
        }
    end
end