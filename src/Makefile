DMD?=dmd
DFLAGS=-m64 -gc

BUILD_GEN_INDEX_OBJS=gen_index.o config.o aws.o s3.o
BUILD_GEN_INDEX_LIBS=-L-lcrypto -L-lcurl

all: build-gen-index

%.o: %.d
	$(DMD) -c $(DFLAGS) $<

clean:
	rm -f $(BUILD_GEN_INDEX_OBJS) build-gen-index

build-gen-index: $(BUILD_GEN_INDEX_OBJS)
	$(DMD) $(DFLAGS) -of$@ $(BUILD_GEN_INDEX_OBJS) $(BUILD_GEN_INDEX_LIBS)
