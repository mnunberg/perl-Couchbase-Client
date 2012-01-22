#include "perl-couchbase.h"
void plcb_convert_storage(
    PLCB_t *object, SV **data_sv, STRLEN *data_len,
    uint32_t *flags)
{
    dSP;
    
    SV *sv;
    SV *compressed_sv;
    SV *result_sv;
    
    int count;
    
    
    if(!(object->my_flags & PLCBf_DO_CONVERSION || SvROK(*data_sv) ) ) {
        return;
    }
    
    sv = *data_sv;
    if(SvROK(sv)) {
        if(!(object->my_flags & PLCBf_USE_STORABLE)) {
            die("Serialization not enabled "
                "but we were passed a reference");
        }
        //warn("Serializing...");
        
        ENTER;
        SAVETMPS;
        
        PUSHMARK(SP);
        XPUSHs(sv);
        PUTBACK;
        
        count = call_sv(object->cv_serialize, G_SCALAR);
        
        SPAGAIN;
        
        if (count != 1) {
          croak("Serialize method returned nothing");
        }
    
        sv = POPs;
        SvREFCNT_inc(sv);
        PUTBACK;
        
        FREETMPS;
        LEAVE;
        
        *data_len = SvLEN(sv);
        *data_sv = sv;
        plcb_storeflags_apply_serialization(object, *flags);
    }
    
    if( (object->my_flags & PLCBf_USE_COMPRESSION)
       && object->compress_threshold
       && *data_len >= object->compress_threshold ) {
        
        //warn("Compressing..");
        
        compressed_sv = newSV(0);
        
        PUSHMARK(SP);
        
        XPUSHs(sv_2mortal(newRV_inc(sv)));
        XPUSHs(sv_2mortal(newRV_inc(compressed_sv)));
        
        PUTBACK;
        
        count = call_sv(object->cv_compress, G_SCALAR);
    
        SPAGAIN;
        
        if (count < 1) {
          croak("Compress method returned nothing");
        }
        
        result_sv = POPs;
        PUTBACK;

        if (SvTRUE(result_sv)) {
            sv = compressed_sv;
            plcb_storeflags_apply_compression(object, *flags);
            *data_len = SvLEN(sv);
            *data_sv = sv;
        } else {
            SvREFCNT_dec(compressed_sv);
        }
    }
}

void plcb_convert_storage_free(PLCB_t *object, SV *data, uint32_t flags)
{
    if(plcb_storeflags_has_compression(object, flags) == 0 &&
       plcb_storeflags_has_serialization(object,flags) == 0) {
        return;
    }
    SvREFCNT_dec(data);
}

SV* plcb_convert_retrieval(
    PLCB_t *object, const char *data, size_t data_len, uint32_t flags)
{
    SV *ret_sv, *input_sv;
    dSP;
    
    input_sv = newSVpvn(data, data_len);
    
    if(!plcb_storeflags_has_conversion(object, flags)) {
        return input_sv;
    }
    
    ret_sv = NULL;
    
    if(plcb_storeflags_has_compression(object, flags)) {
        ret_sv = newSV(0);
        //warn("Decompressing..");
        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newRV_inc(input_sv)));
        XPUSHs(sv_2mortal(newRV_inc(ret_sv)));
        PUTBACK;
        
        if(call_sv(object->cv_decompress, G_SCALAR|G_EVAL) < 1) {
            die("decompress method didn't return anything");
        }
        SPAGAIN;
        if(!SvTRUE(POPs)) {
            SvREFCNT_dec(ret_sv);
            ret_sv = NULL;
        } else {
            //sv_dump(input_sv);
            SvREFCNT_dec(input_sv);
            input_sv = NULL;
        }
    }
    
    if(plcb_storeflags_has_serialization(object, flags)) {
        if(ret_sv) {
            /*if we decompressed, let the input_sv be the decompressed data
             which we are about to deserialize*/
            input_sv = ret_sv;
        }
        //warn("Deserializing..");
        ret_sv = NULL;
        
        ENTER;
        SAVETMPS;
        PUSHMARK(SP);
        XPUSHs(input_sv);
        PUTBACK;
        
        if(call_sv(object->cv_deserialize, G_SCALAR|G_EVAL) < 1) {
            die("Deserialize method didn't return anything");
        }
        if(!SvTRUE(ERRSV)) {
            ret_sv = POPs;
            SvREFCNT_inc(ret_sv);
            SvREFCNT_dec(input_sv);
            input_sv = NULL;
        } else {
            ret_sv = input_sv;
            warn(SvPV_nolen(ERRSV));
        }
        FREETMPS;
        LEAVE;
    }
    return ret_sv;
}