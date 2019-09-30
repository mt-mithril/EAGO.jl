*****************************************************************
*** Chapter 6
*** Test Problem 11
***
*** Ethanol - Benzene - Water -- tangent plane distance minimization(UNIFAC)
*****************************************************************

SETS
    i     components                /1*3/
    m     groups                    /1*3/
    alias(i,j)
    alias(m,l);

*****************************************************************
* P = pressure (atm)
* T = temperature (K)
* feed(i) = mole fraction of component i in candidate phase (feed)
* chempot(i) = chemical potential of component i in candidate phase
* z, zr(i), zrm, zb(i), za, psi(i), q(i), r(i), nu(i),
*    vhat(m,i), lambda(m,i) = pure component and calculated parameters
* v(m,i) = group-component matrix
* bigq(m), bigr(m) = group parameters

PARAMETERS
gc, P, T, feed(i), chempot(i), gform(i),
minval,
z, bigq(m), bigr(m), v(m,i), zr(i), zrm, zb(i), za, psi(i), tau(m,l), bip(m,l),
q(i), r(i), vhat(m,i), lambda(m,i), nu(i);

P = 1.0;
T = 298.0;
gc = 1.98721;

feed('1') = 0.2;
feed('2') = 0.4;
feed('3') = 0.4;

chempot('1') = -3.50404;
chempot('2') = -2.08956;
chempot('3') = -3.78836;

gform('1') = -2.562164;
gform('2') = -2.084538;
gform('3') = -3.482138;

z = 10.0;

bigq('1') = 1.972;
bigq('2') = 0.400;
bigq('3') = 1.400;

bigr('1') = 2.1055;
bigr('2') = 0.5313;
bigr('3') = 0.9200;

v('1','1') = 1; v('1','2') = 0; v('1','3') = 0;
v('2','1') = 0; v('2','2') = 6; v('2','3') = 0;
v('3','1') = 0; v('3','2') = 0; v('3','3') = 1;

tau('1','1') = 0.0; tau('1','2') = 89.6; tau('1','3') = 353.5;
tau('2','1') = 636.1; tau('2','2') = 0.0; tau('2','3') = 903.8;
tau('3','1') = -229.1; tau('3','2') = 362.3; tau('3','3') = 0.0;

bip(m,l) = EXP(-tau(m,l)/T);
q(i) = SUM(m, v(m,i)*bigq(m));
r(i) = SUM(m, v(m,i)*bigr(m));
zr(i) = (z*q(i)/2.0 - 1.0)/r(i);
minval = 100.0;
LOOP(i, IF( (zr(i) LT minval), minval = zr(i)));
zrm = minval;
za = zrm + SUM(i,zr(i)-zrm);
zb(i) = SUM(j$(ord(j) NE ord(i)), zr(j)-zrm);
psi(i) = q(i) + r(i)*(zr(i)+zb(i));

vhat(m,i) = SUM(l, bigq(l)*v(l,i)*bip(l,m));
lambda(m,i) = EXP(bigq(m)*(1-LOG(vhat(m,i)/q(i))
                            -SUM(l,v(l,i)*bigq(l)*bip(m,l)/vhat(l,i))));
*nu(i) = SUM(m, v(m,i)*lambda(m,i));
nu(i) = 0.0;


DISPLAY psi, zr, zb, za, bip, vhat, nu;
*******************************************************************
* dist = tangent plane distance function
* x(i) = mole fraction of component i

VARIABLES dist, x(i);

*******************************************************************
* obj = objective function
* molesum = mole fractions sum to 1

EQUATIONS
    obj
    molesum;


obj.. dist =e= SUM(i, x(i)*(gform(i)-chempot(i)-zr(i)*r(i)*LOG(r(i))
                            + z*q(i)*LOG(q(i))/2.0 - nu(i)))
              +SUM(i, za*r(i)*x(i))*LOG(SUM(j,r(j)*x(j)))
              +SUM(i, zb(i)*r(i)*x(i)*LOG(x(i)/SUM(j, r(j)*x(j))))
              +SUM(i, (z/2.0)*q(i)*x(i)*LOG(x(i)/SUM(j,q(j)*x(j))))
              +SUM(i, q(i)*x(i))*LOG(SUM(j,q(j)*x(j)))
      +SUM(i, SUM(m, x(i)*v(m,i)*bigq(m)*LOG(x(i)/SUM(j,vhat(m,j)*x(j)))))
              +SUM(i, -psi(i)*x(i)*LOG(x(i)));

molesum.. SUM(i, x(i)) =e= 1.0;

MODEL tpd / all /;

x.lo(i) = 0.000001; x.up(i) = 1.0;
x.l('1') = 0.00565;
x.l('2') = 0.99054;
x.l('3') = 0.00381;

SOLVE tpd USING nlp MINIMIZING dist;
