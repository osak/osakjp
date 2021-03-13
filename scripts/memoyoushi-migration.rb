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

GOOGLE_ANALYTICS = <<END
<!-- Global site tag (gtag.js) - Google Analytics -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-K7GK6FJ729"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());

  gtag('config', 'G-K7GK6FJ729');
</script>
END
GOOGLE_ANALYTICS_MARK = GOOGLE_ANALYTICS.lines.first

def patch_html(filename)
    has_analytics = false
    sed_i(filename) { |line|
        if line == GOOGLE_ANALYTICS_MARK
            has_analytics = true
        end
        if line.match(/<script src=/)
            ""
        else
            result = line.gsub(/(<link.*)style.css(")/) { "#{$1}style_memoyoushi.css#{$2}" }
                .gsub(%r{(<a.*href=".*)index.html(".*>メモ用紙2.0</a>)}) { "#{$1}index_memoyoushi.html#{$2}" }
                .gsub(%r{(class="kogarasi-mark".*>)(</div>)}) { "#{$1}ここにはかつてコメントが表示されていました#{$2}" }
            if !has_analytics && line.match(%r{</head>})
                result = "#{GOOGLE_ANALYTICS}\n</head>"
            end
            result
        end
    }
end

dirs = %w(diary trip program other hardware linux food)

dirs.each do |dir|
    Dir.glob("memoyoushi-archive/#{dir}/**/*.html") do |path|
        puts path
        patch_html(path)
    end
end
patch_html("memoyoushi-archive/about_me.html")
patch_html("memoyoushi-archive/about.html")
patch_html("memoyoushi-archive/index_memoyoushi.html")