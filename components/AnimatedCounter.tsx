'use client';
import CountUp from 'react-countup';

const AnimatedCounter = ({ amount }: { amount: number }) => {
  return (
    <div className='w-full'>
      <CountUp
        end={amount}
        decimal='.'
        decimals={2}
        suffix='€'
        duration={1}
      />
    </div>
  );
};

export default AnimatedCounter;
