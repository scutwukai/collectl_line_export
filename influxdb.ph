use bytes;
use LWP::UserAgent;
use HTTP::Request;

my $hostname='';
my $influxdbSockHost;
my $influxdbSockPort;
my $influxdbWriteDB='';
my $influxdbUseRP='default';
my $influxdbDebug;

my $influxdbTags;
my $influxdbTimestamp;
my $influxdbMeasure; 
my @influxdbFields;
my @influxdbValues;
my @influxdbHttpBuf;




sub influxdbInit {
    my $hostport=shift;
    error("host[:port] must be specified as first parameter")    if !defined($hostport);

    # parameter defaults
    $hostport      .= ":8086"    if $hostport!~/:/;
    $influxdbDebug  = 0;

    if ($hostname eq '') {
        $hostname = `hostname`;
        chomp $hostname;
    }

    # parsing
    ($influxdbSockHost, $influxdbSockPort)=split(/:/, $hostport);

    foreach my $option (@_) {
        my ($name, $value)=split(/=/, $option);
        error("invalid influxdb option '$name'")    if $name!~/^[dwhr]?$/;

        $influxdbDebug=$value       if $name eq 'd';
        $influxdbWriteDB=$value     if $name eq 'w';
        $influxdbUseRP=$value       if $name eq 'r';
        $hostname=$value            if $name eq 'h';
    }

    error("the influxdb database name must be spec")    if $influxdbWriteDB eq '';
}

sub influxdb {
    $influxdbTimestamp = time;
    $influxdbTags      = "host=$hostname";
    @influxdbHttpBuf   = ();

    if ($subsys=~/c/) {
        # CPU utilization is a % and we don't want to report fractions
        my $i=$NumCpus;

        newData('cputotals');
        addData('user', 'percent', $userP[$i]);
        addData('nice', 'percent', $niceP[$i]);
        addData('sys',  'percent', $sysP[$i]);
        addData('wait', 'percent', $waitP[$i]);
        addData('idle', 'percent', $idleP[$i]);
        addData('irq',  'percent', $irqP[$i]);
        addData('soft', 'percent', $softP[$i]);
        addData('steal','percent', $stealP[$i]);
        bufData();

        newData('ctxint');
        addData('ctx',  'switches/sec', $ctxt/$intSecs);
        addData('int',  'intrpts/sec',  $intrpt/$intSecs);
        addData('proc', 'pcreates/sec', $proc/$intSecs);
        addData('runq', 'runqSize',     $loadQue);
        bufData();

        # these are the ONLY fraction, noting they will print to 2 decimal places
        newData('cpuload');
        addData('avg1',  'loadAvg1',  $loadAvg1,  2);
        addData('avg5',  'loadAvg5',  $loadAvg5,  2);
        addData('avg15', 'loadAvg15', $loadAvg15, 2);
        bufData();
    }

    if ($subsys=~/d/)
    {
        newData('disktotals');
        addData('reads',    'reads/sec',    $dskReadTot/$intSecs);
        addData('readkbs',  'readkbs/sec',  $dskReadKBTot/$intSecs);
        addData('writes',   'writes/sec',   $dskWriteTot/$intSecs);
        addData('writekbs', 'writekbs/sec', $dskWriteKBTot/$intSecs);
        bufData();
    }

    sendData()
}

sub newData {
    $influxdbMeasure = shift;
    @influxdbFields  = ();
    @influxdbValues  = ();
}

sub addData {
    my $field = shift;
    my $units = shift;
    my $value = shift;
    my $numpl = shift;    # number of decimal places

    $value=sprintf("%.${numpl}f", $value)   if defined($numpl);
    $value=int($value)                      if !defined($numpl);

    @influxdbFields = (@influxdbFields, $field);
    @influxdbValues = (@influxdbValues, $value);
}

sub bufData {
    my $fieldList = '';

    for (my $i=0; $i<@influxdbFields; $i++) {
        $fieldList .= "$influxdbFields[$i]=$influxdbValues[$i]";
        if ($i < @influxdbFields - 1) {
            $fieldList .= ',';
        }
    } 

    @influxdbHttpBuf = (@influxdbHttpBuf, "$influxdbMeasure,$influxdbTags $fieldList $influxdbTimestamp\n")
}

sub sendData {
    my $content = "";
    for (my $i=0; $i<@influxdbHttpBuf; $i++) {
        $content .= "$influxdbHttpBuf[$i]";
    }

    if ($influxdbDebug & 1) {
        print $content;
        print "\n---------------------------\n";
        return;
    }

    my $request = new HTTP::Request 'POST', "http://$influxdbSockHost:$influxdbSockPort/write?db=$influxdbWriteDB&precision=s&rp=$influxdbUseRP";
    $request->header('content-length' => bytes::length($content));
    $request->header('content-type' => 'text/plain');
    $request->content($content);

    if ($influxdbDebug & 2) {
        print $request->as_string();
        print "\n---------------------------\n";
        return;
    }

    my $ua = new LWP::UserAgent;
    my $response = $ua->request($request);
    print $response->error_as_HTML()       if !$response->is_success();
}

1;
