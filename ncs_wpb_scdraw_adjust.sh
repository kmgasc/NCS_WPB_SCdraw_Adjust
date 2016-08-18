#!/bin/bash
set +x                                                   # disable command echo

export Site="${1}";                              # Site Abbrv
export CMjob="${2}";                        # Control-M Job name
export PUB="${3}";                            # Publication to process
export AdjFile="${4}";                        # Input adjustment file
export Datafile="${5}";                       # Input data file
export Outfile="${6}";                        # Adjusted output file
export Excfile="${7}";                         # Adjustment and/or Invalid input data exception ifle

export SUBJ="INFORMATION | ${CMjob} Exceptions for Pub:${PUB}";             # Subject line of email
export EADDR="/home/keithg/scripts/${CMjob}.txt";                           # Fully qualified file name of email addresses to send to

echo -c "\nBegin ${CMjob} at $(date)";
if [ -f ${Outfile} ]; then
   /bin/rm ${Outfile};                           # remove old output file
fi
if [ -f ${Excfile} ]; then                         # remove old exceptions file
   /bin/rm ${Errfile};
fi

if [ -f ${Datafile} ]; then                       # Must have at least the input data file
   ls -l ${Datafile};
else
    echo "ERROR: file ${Datafile} Not found";
    exit 1;
fi

if [ -f ${AdjFile} ]; then                       # If no adjust file, the input file will just pass thru as is, unless a data file record exception is found
   ls -l ${AdjFile};
else
    echo "WARNING: file ${AdjFile} Not found";
fi

if [ -f ${EADDR} ]; then                       # If no email address list file then create one
   ls -l ${EADDR};
else
    echo "Creating Email List file ${EADDR}";
    echo "CMGDTICSGA@COXINC.COM" > ${EADDR};
    if [ ${?} -ne 0 ]; then
       echo "ERROR: Cannot create Email List file ${EADDR}";
       exit 1;
    fi
    chmod 666  ${EADDR} >/dev/null 2>&1;
fi
############################################### now stream in the adjust file, a file separtor & the data input file
echo "Running adjustment process..."
(cat ${AdjFile} 2>/dev/null;echo "EOFxx..";cat ${Datafile}) | /bin/gawk -F"|" -v PUB="${PUB}"  >${Outfile} 2>${Excfile} \
'BEGIN {
  vDbug=0                                  # True debug. False/True = 0/1
  vLdAry=1                                 # True load array
  vSumTotal=0                              # New adjusted Summary Total
  vRecTotal=0                              # New D type record counter in case there are route amount exceptions in data file
  OFS=FS                                   # Set oupt field separator the same as command line separator
                                                  # otherwise an adjustment applied to $0 prints with space separating the fields
  if (vDbug)
     {print("Begin") > "/dev/stderr"
      print("Get Adjustment for PUB: "PUB) > "/dev/stderr"
      print("End Begin") > "/dev/stderr"
     }
}
function ltrim(s) { sub(/^[ \t\r\n]+/, "", s); return s }
function rtrim(s) { sub(/[ \t\r\n]+$/, "", s); return s }
function trim(s) { return rtrim(ltrim(s)); }
function validAdj(fstr) {
  fsign=substr(fstr,1,1)                   # substring out the 1st char
  if(fsign == "+" || fsign == "-")         # A leading + or - sign?
    {if(length(fstr) == 1)
        return 0                           # No number following the sign, adj is invalid
     else
        fnum=rtrim(substr(fstr,2,1))       # substring out & right trim out white space of the integer adjustment
    }
  else
     fnum=rtrim(substr(fstr,1))            # no sign, just a right trimmed out number.

  if(fnum ~ /^[0-9]+$/)                    # every char must be a digit. No leading white space allowed
     return 1                              # adjustment sign & integer value is valid
  else
     return 0                              # string has something in it other than digits, so it is invalid
}
function fdoAdj(fstr)
{
  fnum=""
  fsign=substr(fstr,1,1)                   # substring out the leading + or - sign, if one
  if(fsign == "+" || fsign == "-")
     fnum=substr(fstr,2)                   # substring out the integer adjustment
  else
     fnum=fstr                             # no sign so just get the adjustment replacement amount

  if(fsign == "+")                         # Add adjustment to current record amount
    { if(vDbug) print("Positive fdoAdj: "$10" + "fnum)
      $10=($10 + fnum)
    }
  else if(fsign == "-")                    # Subtract adjustment from current record amount
    { if(vDbug) print("Negative fdoAdj: "$10" - "fnum)
      $10=($10 - fnum)
      if($10 < 0) $10=0                    # do not go negative
    }
  else                                     # Replace current record amount with adjustment
    { if(vDbug) print("Replacement fdoAdj:fstr="fnum)
      $10=fnum
    }
}
function ffileproc()
{
  if($10 ~ /^[0-9]+$/)                    # Route amount must be an integer
    {fadjstr=""
     if ($4 in AdjArry)                   # if route is found
        {fadjstr=AdjArry[$4]              # then get adjustment string
         fdoAdj(fadjstr)                  # then do adjustment in route amount field
        }
    }
  else
     {print($0"|Column 10:Amount must be an Integer|") > "/dev/stderr"
      return 1                            # cannot write bad integer value to file since it will cause Summary to be off
     }

  print($0)                               # Print record as is
  vSumTotal=vSumTotal+$10                 # Add up Route amount after adjustment
  vRecTotal++                             # Count D type records in case Route amount is not numeric
}
function fsumry()
{
   $4=vRecTotal                           # set new record counter
   $5=vSumTotal                           # set new Summary amount
   print($0)                              # print new S type summary record
}
########################################### Begin Main Here
{
  if ($1 == "EOFxx..")                    # Separates Input adjustments file from data file to adjust
     {vLdAry=0;                           # Turn off Load Array
      if(vDbug)
        { for(fitem in AdjArry)
             { print(fitem" "AdjArry[fitem]) }
        }
      next;
     }
  if(vLdAry)
    { if($1==PUB)                                     # Get adjustments for this Publication only
      {if(length($2) == 0 || length($3) == 0)         # skip blank Routes or Adjustment Nbrs
        {print($0"|Invalid/Blank Adjustment") > "/dev/stderr"
         next
        }
       if(validAdj($3))
          AdjArry[$2] = $3                            # if the adjust is valid put it in associative array
       else
          print($0"|Invalid Adjustment Amount") > "/dev/stderr"
      }
    }
  else
     { if($1 == "D")                                  # Looks like this is the record type to apply adjustment to
          ffileproc()
       else
          if($1 == "S")
            fsumry()                                  # Process summary record with new grand total
          else
             print($0)                                # otherwise just pass the data record thru as is
     }
}
END {
  if(vDbug) print("End awk script") > "/dev/stderr"
}';

ls -l ${Outfile};
chmod 666 ${Outfile} >/dev/null 2>&1;                                                                      # set permissions
grep ^D ${Outfile}| awk -F"|" 'BEGIN {t=0} {t=t+$10} END {print(t)}';                       # just an FYI resum the route amounts
chmod 666 ${Excfile}  >/dev/null 2>&1;
if [ -s ${Excfile} ]; then                                                                                                      # Execption file exists and has a size > 0 email it out
   echo "Emailing Exception file ${Excfile} to Users in file ${EADDR}";
   mutt -s "${SUBJ}" -a "${Excfile}" -- "$(cat ${EADDR})";                                             # after all this now email the attachment
   retcode=${?};                                                                                                                  # save the return code for later
   sleep 3;
   if [ ${retcode} -ne 0 ]; then
      echo -e "\n   mutt command failed: mutt -s ${SUBJ} -a ${Excfile} -- $(cat ${EADDR}); \n";
      exit ${retcode};
   fi;
fi
echo -c "\nEnd ${CMjob} at $(date)";
exit 0;



