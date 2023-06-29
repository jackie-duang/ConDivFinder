use warnings;
use strict;
use Getopt::Long;

my $usage = <<USAGE;
Usage:
    perl $0 -in <input.fasta> -l <species.list> -w <window size> -con <conserved number> -div <changed number> -bn <background can not conserved species>
    
    -w window size : default 20 , the window size for calculating the conserved region
    -con conserved number : default 18 , identify as conserved region if the number of nucleotides in the window is large or equal to this value
    -div changed number : default 12 , identify as changed region if the number of nucleotides in the window is less or equal to this value
    -bn background can not conserved species : default 0 , how many species can not be conserved in the background species
    ---
    species list file format, one species per line and foreground species marked with '*':
    human
    mouse
    snake *
    frog 
    caecilian *
    ...

    fasta file format: # species name should not contain '.' '-' '@' etc. ; '_' is allowed ; the first species should be the reference species
    >species_name
    AAGCTTGGG
    or 
    >species_name.seqId
    AAGCTTGGG
USAGE

# get options
my ($in,$window,$speciesList, $conservedNumber, $changedNumber, $canChanged);

GetOptions(
    "in=s" => \$in,
    "w=i" => \$window,
    "l=s" => \$speciesList,
    "con=i" => \$conservedNumber,
    "div=i" => \$changedNumber,
    "bn=i" => \$canChanged,
);

# set default value
$window = 20 if (!defined $window);
$conservedNumber = 18 if (!defined $conservedNumber);
$changedNumber = 12 if (!defined $changedNumber);
$canChanged = 0 if (!defined $canChanged);

# check options
die $usage if (!defined $in or !defined $speciesList);

my %info ;
my %seq ;
my $length = 0;
my %addInfo ;
my $line = 0;
my %mapSites ;
my $ref = '' ;

my $file_prefix = "$in.win$window";
my $out = "$file_prefix.info";

$/ = ">";
my %speciesLocs = ();
my %speciesNucls = ();
my %original_pos = ();
open I , "< $in";
while (<I>){
    chomp;
    my @a = split /\n+/,$_ ;
    next if @a==0 ;

    # get id and sequence
    my $id = shift @a ;
    $id =~ /^(\w+)/;
    $id = $1 ;
    my $seq = join '',@a ;
    $seq = uc($seq);

    # record the length of the longest id
    if (length($id) > $length){
        $length = length($id);
    }

    # record the number of nucleotides in each species
    my @nucls = split //,$seq;
    my $start = 1 ;
    if ($ref eq ''){
        $ref = $id;
        my $ref_site = 0 ;

        # record the nucleotide at each site in the reference species
        for (my $i=0;$i<@nucls;$i++){
            $mapSites{$i} = $ref_site ;
            next if ($nucls[$i] eq '-');
            $ref_site ++ ;
            $seq{'ref'}{$i} = $nucls[$i];
            $original_pos{$i} = $start + $ref_site - 1;
        }
    }
    else{
        my $window_id = 0 ;
        my $step = 0 ;
        my %map = ();

        # record the nucleotide at each site in each species and calculate the number of conserved nucleotides in each window
        for (my $i=0;$i<@nucls;$i++){
            if ((exists $seq{'ref'}{$i}) or ($nucls[$i] ne '-')){
                $step ++ ;
                $map{$step} = $i ;

                if ((exists $seq{'ref'}{$i}) and ($nucls[$i] eq $seq{'ref'}{$i})){
                    $window_id ++ ;
                }
                
                if ($step >= $window){
                    $addInfo{$id}{$map{$step-$window+1}} = $window_id;
                    
                    if ((exists $seq{'ref'}{$map{$step-$window+1}}) and ($nucls[$map{$step-$window+1}] eq $seq{'ref'}{$map{$step-$window+1}})){
                        $window_id -- ;
                    }
                }
            }
        }
    }
}
close I ;
$/ = "\n";

my %backgroundSpecies ;
my %foregroundSpecies ;

# read species list and record the foreground species and background species
open I, "< $speciesList" or die $!;
while (<I>){
    chomp;
    next if $_ =~ /^$/ ;
    my @a = split /\s+/, $_ ;
    $line ++ ;
    $info{$line}{id} = $a[0] ;
    if (@a>1 and $a[1] eq '*'){
        $foregroundSpecies{$a[0]} = 1 ;
    }
    else{
        next if ($a[0] eq $ref);
        $backgroundSpecies{$a[0]} = 1 ;
    }
}
close I ;

my %hash = () ;

open O , "> $out";
printf O "%-${length}s", "originalPos";
foreach my $k (sort {$a <=> $b} keys %{$seq{'ref'}}){
    printf O " %-4d",$mapSites{$k} + 1;
}
print O "\n";

printf O "%-${length}s", "alignedPos";
foreach my $k (sort {$a <=> $b} keys %{$seq{'ref'}}){
    printf O " %-4d",$k + 1;
}
print O "\n";

foreach my $line (sort {$a <=> $b} keys %info){
    my $id = $info{$line}{id};
    printf O "%-${length}s", $id;
    foreach my $k (sort {$a <=> $b} keys %{$seq{'ref'}}){
        if ($id eq $ref){
            printf O " %-4d", $window;
            next ;
        }
        my $title = sprintf "%-4d",$k + 1;
        if (exists $addInfo{$id}{$k}){
            printf O " %-4d", $addInfo{$id}{$k};
            $hash{$title}{$id} = $addInfo{$id}{$k};
        }else{
            printf O (" %-4d", 0);
            $hash{$title}{$id} = 0;
        }
    }
    print O "\n";
}
close O ;

%hash = ();
my @positions ;
open I , "< $out";
while (<I>){
    chomp;
    my @a = split /\s+/,$_;
    next if @a==0 ;
    if ($a[0] eq 'originalPos'){
        @positions = @a ;
		<I>;
        next ;
    }
    my $species = $a[0] ;
    next if $species eq $ref ;
    for (my $i=1;$i<@a;$i++){
        $hash{$positions[$i]}{$species} = $a[$i] ;
    }
}
close I ;

open O , "> $out.conserved.list";
print O "file\toriginalPositionBasedRef\tforegroundChangedSpecies\tbackgroundNotConservedSpecies\n";
foreach my $pos (sort {$a <=> $b} keys %hash){
    my $notConservedNumber = 0 ;
    my %notConservedSpecies = ();
    foreach my $tpSp (sort keys %backgroundSpecies){
        if (exists $hash{$pos}{$tpSp}){
            if ($hash{$pos}{$tpSp} < $conservedNumber){
                $notConservedNumber ++ ;
                $notConservedSpecies{$tpSp} = $hash{$pos}{$tpSp} ;
            }
        }
        else{
            $notConservedNumber ++ ;
            $notConservedSpecies{$tpSp} = 0 ;
        }
    }

    next if $notConservedNumber > $canChanged ;

    my %changedSpecies = ();
    foreach my $sp (sort keys %foregroundSpecies){
        if (exists $hash{$pos}{$sp}){
            if ($hash{$pos}{$sp} <= $changedNumber and $hash{$pos}{$sp} >= 0){
                $changedSpecies{$sp} = $hash{$pos}{$sp} ;
            }
        }
        else{
            $changedSpecies{$sp} = 0 ;
        }
    }

    print O "$in\t$pos\t";
    my $changedSpLine = '#';
    foreach my $sp (sort keys %changedSpecies){
        next if $changedSpecies{$sp} eq 'NA' ;
        $changedSpLine .= "$sp," ;
    }
    $changedSpLine =~ s/,$// ;
    print O "$changedSpLine\t";
    my $notConservedSpLine = '#';
    foreach my $sp (sort keys %notConservedSpecies){
        $notConservedSpLine .= "$sp," ;
    }
    $notConservedSpLine =~ s/,$// ;
    print O "$notConservedSpLine\n";
}
close O ;