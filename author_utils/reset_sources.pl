#!/usr/bin/perl
use strict;
use warnings;
use Dir::Self;
use lib __DIR__ . "../";
use PLCB_ConfUtil;

PLCB_ConfUtil::clean_cbc_sources();