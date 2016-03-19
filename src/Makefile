DMD?=dmd
DFLAGS?=

BUILD_GEN_INDEX_SRCS=gen_index.d config.d aws.d s3.d
BUILD_GEN_INDEX_LIBS=-L-lcrypto -L-lcurl

all: build-gen-index

clean:
	rm -f build-gen-index

build-gen-index: $(BUILD_GEN_INDEX_SRCS)
	$(DMD) $(DFLAGS) -of$@ $(BUILD_GEN_INDEX_SRCS) $(BUILD_GEN_INDEX_LIBS)
