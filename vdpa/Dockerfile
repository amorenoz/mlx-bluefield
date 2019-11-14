FROM fedora:29

RUN yum groupinstall -y "Development Tools"
RUN yum install -y wget numactl-devel git make

WORKDIR /usr/src
ENV RDMA_CORE_VER stable-v25
ENV RDMA_CORE_PATH=/usr/src/rdma-core-$RDMA_CORE_VER
WORKDIR /usr/src/
RUN wget https://github.com/linux-rdma/rdma-core/archive/${RDMA_CORE_VER}.zip
RUN ls; unzip  ${RDMA_CORE_VER}.zip
WORKDIR ${RDMA_CORE_PATH}
RUN yum -y install cmake gcc libnl3-devel libudev-devel pkgconfig valgrind-devel ninja-build python3-devel python3-Cython
RUN ls -lha 
RUN ./build.sh

#ENV DPDK_VER 19.08
ENV DPDK_DIR /usr/src/vdpaDriver/
WORKDIR /usr/src/
RUN wget http://file.mad.redhat.com/~amorenoz/vdpaDriver.tar.gz
RUN tar -xpvf vdpaDriver.tar.gz

WORKDIR ${DPDK_DIR}
ADD 0001-vdpa_hack-revert-configure-vdpa-device-on-vring-call.patch ${DPDK_DIR}
ADD 0002-mlx5-fix-debug-compilation.patch ${DPDK_DIR}
RUN patch -p1 < 0001-vdpa_hack-revert-configure-vdpa-device-on-vring-call.patch
RUN patch -p1 < 0002-mlx5-fix-debug-compilation.patch

ENV RTE_TARGET=x86_64-native-linuxapp-gcc
ENV RTE_SDK=${DPDK_DIR}/
# DPDK_VER 19.08
RUN sed -i -e 's/EAL_IGB_UIO=y/EAL_IGB_UIO=n/' config/common_linux
RUN sed -i -e 's/KNI_KMOD=y/KNI_KMOD=n/' config/common_linux
RUN sed -i -e 's/LIBRTE_KNI=y/LIBRTE_KNI=n/' config/common_linux
RUN sed -i -e 's/LIBRTE_PMD_KNI=y/LIBRTE_PMD_KNI=n/' config/common_linux
RUN sed -i -e 's/CONFIG_RTE_LIBRTE_MLX5_PMD=n/CONFIG_RTE_LIBRTE_MLX5_PMD=y/' config/common_base
RUN sed -i -e 's/CONFIG_RTE_LIBRTE_MLX5_DEBUG=n/CONFIG_RTE_LIBRTE_MLX5_DEBUG=y/' config/common_base

RUN make -j4 install T=${RTE_TARGET} DESTDIR=${RTE_SDK}  EXTRA_CFLAGS="-I$RDMA_CORE_PATH/build/include " EXTRA_LDFLAGS="-L$RDMA_CORE_PATH/build/lib"
RUN make -C examples/vdpa T=${RTE_TARGET} EXTRA_CFLAGS="-I$RDMA_CORE_PATH/build/include " EXTRA_LDFLAGS="-L$RDMA_CORE_PATH/build/lib"
RUN cp examples/vdpa/build/app/vdpa /usr/bin/vdpa

ENV LD_LIBRARY_PATH=${RDMA_CORE_PATH}/build/lib

