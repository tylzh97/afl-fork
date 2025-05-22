{
  description = "简化版 C 语言项目开发环境";

  # 输入源
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-24.11"; 
    flake-utils.url = "github:numtide/flake-utils";   
  };

  # 输出配置
  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # 系统特定的包集
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = false;
            permittedInsecurePackages = [
              "python-2.7.18.8"
            ];
          };
        };
        
        lib = pkgs.lib;

        # 定义需要网络下载的依赖
        qemuSrc = pkgs.fetchurl {
          url = "https://download.qemu.org/qemu-2.10.0.tar.xz";
          sha256 = "55d81ac987a4821d2744359c026d766459319ba9c013746570369068d93ff335";
        };
        
        # 基本依赖组
        # 构建工具
        buildTools = with pkgs; [ 
          gcc 
          gnumake 
          pkg-config 
          python
          automake
          autoconf
          bison
          which
          wget
        ];                  
        # 核心依赖
        coreDeps = with pkgs; [ 
          glibc 
          glib 
          zlib
          libtool
        ];                           
        # 开发工具
        devTools = with pkgs; [ 
          gdb 
          valgrind 
          clang-tools 
          cppcheck 
        ];         
        
        # 可自定义的 C 语言项目构建函数
        buildCProject = { 
          pname ? "AFL",     # 项目名称
          version ? "0.1.0",       # 项目版本
          enableDebug ? false      # 是否启用调试
        }:
          pkgs.stdenv.mkDerivation {
            inherit pname version;
            src = ./.;             # 源代码路径

            # 构建环境
            nativeBuildInputs = buildTools;
            buildInputs = coreDeps;

            # 调试标志
            NIX_CFLAGS_COMPILE = if enableDebug then "-g -O0" else "-O2";

            # 简化构建阶段 - 只使用 gcc 手动编译
            preConfigure = ''
              export NIX_SOURCE_BASE=$PWD
              mkdir -p qemu_mode
              ln -s ${qemuSrc} $PWD/qemu_mode/qemu-2.10.0.tar.xz
            '';

            buildPhase = ''
              cd $NIX_SOURCE_BASE
              echo ">>> 编译项目..."
              make clean all
              cd qemu_mode
              ./build_qemu_support.sh
              echo ">>> 编译完成"
            '';

            # 简化测试阶段
            checkPhase = ''
              cd $NIX_SOURCE_BASE
              echo ">>> 运行测试..."
              pwd
              echo ">>> 测试完成"
            '';

            # 简化安装阶段(需要创建 $out 目录, 然后把编译的结果拷贝到 $out 中. 会在对应在目录中新创建的一个 result 软链接目录, 这个目录在 fixupPhase 阶段非常重要.)
            installPhase = ''
              cd $NIX_SOURCE_BASE
              echo ">>> 安装程序..."
              mkdir -p $out/bin
              find . -maxdepth 1 -type f -name "afl-*" -print0 | while IFS= read -r -d "" file; do
                  if file -b "$file" | grep -q "^ELF"; then
                      cp "$file" $out/bin/
                  fi
              done 
              echo ">>> 安装完成"
            '';

            # 元数据
            meta = with lib; {
              description = "简单的 C 语言项目";
              platforms = platforms.linux;
            };
          };

      in rec {
        # 包定义
        packages = {
          # 默认版本 - 优化模式
          default = buildCProject {
            pname = "AFL";
            version = "0.1.0";
            enableDebug = false;
          };
          
          # 调试版本
          debug = buildCProject {
            pname = "AFL";
            version = "0.1.0";
            enableDebug = true;
          };
        };

        # 开发环境
        devShells.default = pkgs.mkShell {
          # 所有依赖
          packages = buildTools ++ coreDeps ++ devTools;
          
          # 包括一些 Python 包（如需要）
          # ++ (with pkgs.python3Packages; [ numpy matplotlib ]);
          
          # 环境变量
          NIX_CFLAGS_COMPILE = "-I${pkgs.glib.dev}/include/glib-2.0 -I${pkgs.glib.out}/lib/glib-2.0/include";
          NIX_LDFLAGS = "-L${pkgs.glib.out}/lib";
          PKG_CONFIG_PATH = "${pkgs.glib.dev}/lib/pkgconfig";
          
          # 开发环境初始化脚本
          shellHook = ''
            NIX_PATH_ONLY=$(echo $PATH | tr ':' '\n' | grep -E '/nix/store' | tr '\n' ':')
            export PATH=$NIX_PATH_ONLY
            export PATH=$PATH:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.gnugrep}/bin

            PS1='\n\033[1;32m[nix-shell:\w]\$\033[0m '

            echo "==============================================="
            echo "C 语言开发环境已加载"
            echo "==============================================="
            echo "基本命令:"
            echo "  - gcc -o main.elf main.c -lglib-2.0    # 编译"
            echo "  - gdb ./main.elf                       # 调试"
            echo "  - valgrind ./main.elf                  # 内存检查"
            echo "==============================================="
          '';
        };
        
        # 应用定义 - 可通过 nix run 直接执行
        apps.default = {
          type = "app";
          program = "${packages.default}/bin/afl-fuzz";
        };
      }
    );
}
