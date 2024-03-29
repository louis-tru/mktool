######################################################
D_PORT      ?= 9221
PROJ        ?= mktool
MAIN        ?= index.js
COPYS       ?= .cfg*.js
DEPS        ?= deps deps/bclib/deps
######################################################
NODE       ?= node
UNAME      ?= $(shell uname)
BRANCH      = $(shell git branch|grep '*'|cut -d ' ' -f 2)
TARGET     ?= dev stg prod
TARGETS     = $(foreach i,$(TARGET),$(i) $(i)-brk)
T_TARGETS   = $(foreach i,$(TARGET),t_$(i) t_$(i)-brk)
J_TARGETS   = $(foreach i,$(TARGET),j_$(i) j_$(i)-brk)
R_TARGETS   = $(foreach i,$(TARGET),r_$(i) r_$(i)-brk)
R_DIR      ?= ~/hc
CWD        ?= $(shell pwd)
OUT        ?= out/$(PROJ)
ENV        ?= dev
COPYS      += package.json Makefile LICENSE README.md deps/mktool/build.mk
supervisor= $(shell node -e "console.log(path.resolve(require.resolve('supervisor'), '../../../.bin/supervisor'))")
TSC        ?= $(shell which tsc)
######################################################

ifneq ($(USER),root)
	SUDO = "sudo"
endif

ifeq ($(TSC),)
	TSC = ./node_modules/.bin/tsc
endif

IP ?=127.0.0.1

cfg = \
if [ -f .config.js ]; then \
	cat .config.js > config.js; \
elif [ -f .cfg_$(1).js ]; then \
	cat .cfg_$(1).js > config.js; \
elif [ -f cfg/$(1).js ]; then \
	echo "module.exports={...require(\"./cfg/$(1)\")};" > config.js; \
fi

CP = \
	if [ -f "$(1)/package.json" ]; then \
		mkdir -p $(2); \
		cp $(1)/package.json $(2); \
		if [ "$(notdir $(2))" = "somes" ]; then \
			cp $(1)/*.types $(2); \
		fi; \
		if [ -d "$(1)/build" ]; then \
			cp -rf $(1)/build $(2); \
		fi; \
	fi;

r_exec = cd $(OUT); \
	$(NODE) ./deps/mktool/sync_watch.js -u $1 -h $2 $(if $(SYNC),,-d 20000) -t \
		'$(R_DIR)/$(PROJ)/$(OUT)' -i .config.js -i var -i node_modules & \
	ssh $1@$2 'cd $(R_DIR)/$(PROJ)/$(OUT); make j$3'

.PHONY: all build build-install kill init $(TARGETS) $(T_TARGETS) $(R_TARGETS) $(J_TARGETS)

.SECONDEXPANSION:

all: build

build:
	mkdir -p $(OUT)
	cd $(OUT)/.. && ln -sf $(PROJ) dist
	$(call cfg,$(ENV))
	$(foreach i, $(COPYS), mkdir -p $(OUT)/$(dir $(i)); cp -rf $(i) $(OUT)/$(dir $(i));)
	find $(OUT) -name '*.ts'| xargs rm -rf
	$(TSC)
	$(foreach i, $(DEPS), \
		$(foreach j, $(shell ls $(i)), $(call CP,$(i)/$(j),$(OUT)/$(i)/$(j)) \
		) \
	)
	cd $(OUT)/.. && tar -c --exclude $(PROJ)/node_modules -z -f $(PROJ).tgz $(PROJ)

build-install: build
	$(MAKE) -C $(OUT) install
	cd $(OUT) && tar cfz $(PROJ)-all.tgz $(PROJ)

install:
	npm i --unsafe-perm

kill:
	@-$(SUDO) systemctl stop $(PROJ)
	@-cat var/pid|xargs $(SUDO) kill
	@-pgrep -f "$(MAIN)"|xargs kill
	@-pgrep -f "sync_watch.js"|xargs kill

# local debugger start
$(TARGETS):
	@if [ -f $(MAIN) ]; then $(MAKE) j_$@; else $(MAKE) t_$@; fi

# tsc -w
$(T_TARGETS): kill
	ENV=$(subst -brk,,$(subst t_,,$@)) $(MAKE) build
	@-pgrep -f "$(TSC) -w" | xargs kill
	@$(TSC) -w > $(OUT)/output.out 2>&1 &
	@if [ -f .config.js ]; then cp .config.js $(OUT); fi
	$(MAKE) -C $(OUT) j_$(subst t_,,$@)

# js debugger
$(J_TARGETS): kill
	@if [ ! -f config.js  ]; then $(call cfg,$(subst -brk,,$(subst j_,,$@))); fi
	@if [ ! -d node_modules ]; then npm i --unsafe-perm; fi
	@$(supervisor) -w . -i public -i node_modules -- --inspect$(findstring -brk,$@)=0.0.0.0:$(D_PORT) $(MAIN)

# remote debugger
$(R_TARGETS): kill
	@ENV=$(subst -brk,,$(subst r_,,$@)) $(MAKE) build
	@-pgrep -f "$(TSC) -w" | xargs kill
	@$(TSC) -w > $(OUT)/output.out 2>&1 &
	@$(call r_exec,root,$(IP),$(shell echo $@|cut -b 2-10))

init:
	git submodule update --init --recursive